#!/bin/bash

#==============================================================================#
#                           UNIVERSAL TUNNELSMITH                              #
#                      Professional SSH Tunnel Manager                         #
#==============================================================================#

# --- Configuration ---
REMOTE_HOST="103.165.11.123"
REMOTE_USER="root"
SSH_PORT="22"
DB_FILE="/tmp/tunnels.db"

# --- Colors & Styling ---
C_RESET='\033[0m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'
C_BOLD='\033[1m'

mkdir -p /tmp
touch "$DB_FILE"

# --- OS Detection & Auto-Installer ---
check_dependencies() {
    if ! command -v sshpass &> /dev/null; then
        clear
        echo -e "${C_YELLOW}[*] 'sshpass' is missing. Auto-detecting OS to install dependencies...${C_RESET}"
        if command -v pkg &> /dev/null; then
            pkg update -y && pkg install sshpass -y
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update -y && sudo apt-get install sshpass -y
        elif command -v yum &> /dev/null; then
            sudo yum install sshpass -y
        elif command -v pacman &> /dev/null; then
            sudo pacman -Sy sshpass --noconfirm
        else
            echo -e "${C_RED}[!] Could not detect package manager. Please install 'sshpass' manually.${C_RESET}"
            exit 1
        fi
        sleep 2
    fi
}

print_header() {
    clear
    echo -e "${C_CYAN}${C_BOLD}"
    echo "  _____                     _               _ _   _     "
    echo " |_   _|   _ _ __  _ __   ___| |___ _ __ ___(_) |_| |__  "
    echo "   | || | | | '_ \| '_ \ / _ \ / __| '_ \` _ \ | __| '_ \ "
    echo "   | || |_| | | | | | | |  __/ \__ \ | | | | | | |_| | | |"
    echo "   |_| \__,_|_| |_|_| |_|\___|_|___/_| |_| |_|_|\__|_| |_|"
    echo -e "${C_RESET}"
    echo -e "${C_WHITE}               VPS Target: ${C_YELLOW}${REMOTE_HOST}${C_RESET}"
    echo -e "==============================================================\n"
}

pause() {
    echo -e "\n${C_WHITE}Press [ENTER] to return to the menu...${C_RESET}"
    read -r < /dev/tty
}

create_tunnel() {
    echo -e "${C_CYAN}--- Create New Tunnel ---${C_RESET}"
    read -p "Enter the LOCAL Port to forward (e.g., 22, 8080): " LOCAL_PORT < /dev/tty
    read -p "Enter the REMOTE Port for VPS (e.g., 2222, 8080): " REMOTE_PORT < /dev/tty

    if [[ ! "$LOCAL_PORT" =~ ^[0-9]+$ ]] || [[ ! "$REMOTE_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${C_RED}Error: Invalid port number.${C_RESET}"
        return 1
    fi

    echo -e "${C_YELLOW}Establishing TRUE public connection to ${REMOTE_HOST}...${C_RESET}"
    local TMP_LOG=$(mktemp)
    
    sshpass -p '@rey1234' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=15 \
        -N -R 0.0.0.0:$REMOTE_PORT:localhost:$LOCAL_PORT ${REMOTE_USER}@${REMOTE_HOST} -p ${SSH_PORT} >"$TMP_LOG" 2>&1 &
    
    local SSH_PID=$!
    
    # Wait to see if process stays alive
    sleep 2
    
    if ps -p "$SSH_PID" > /dev/null 2>&1; then
        echo "$LOCAL_PORT:$REMOTE_PORT:$SSH_PID" >> "$DB_FILE"
        echo -e "\n${C_GREEN}[SUCCESS] Tunnel Established Successfully!${C_RESET}"
        echo -e "---------------------------------------------------"
        echo -e " Forwarded Port : ${C_WHITE}localhost:$LOCAL_PORT${C_RESET}"
        echo -e " Public IP      : ${C_CYAN}${REMOTE_HOST}${C_RESET}"
        echo -e " Public Port    : ${C_CYAN}${REMOTE_PORT}${C_RESET}"
        echo -e " Connect Command: ${C_YELLOW}ssh <local_user>@${REMOTE_HOST} -p ${REMOTE_PORT}${C_RESET}"
        echo -e "---------------------------------------------------"
        echo -e "${C_RED}[!] NOTE: Ensure Port $REMOTE_PORT is OPEN in your VPS Provider's Web Panel!${C_RESET}"
    else
        echo -e "\n${C_RED}[FAILED] Could not establish tunnel.${C_RESET}"
        echo -e "Debug Log:"
        cat "$TMP_LOG"
    fi
    rm -f "$TMP_LOG"
}

list_tunnels() {
    echo -e "${C_CYAN}--- Active Tunnels ---${C_RESET}"
    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "${C_YELLOW}No active tunnels found.${C_RESET}"
        return
    fi
    printf "${C_WHITE}%-15s | %-15s | %-10s${C_RESET}\n" "Local Port" "Public Port" "Process ID"
    echo "---------------------------------------------------"
    local count=0
    while IFS=: read -r LPORT RPORT PID; do
        if ps -p "$PID" > /dev/null 2>&1; then
            ((count++))
            printf "%-15s | %-15s | %-10s\n" "$LPORT" "$RPORT" "$PID"
        fi
    done < "$DB_FILE"
    if [[ $count -eq 0 ]]; then
        echo -e "${C_YELLOW}No active tunnels (cleared stale data).${C_RESET}"
        > "$DB_FILE"
    fi
}

delete_tunnel() {
    echo -e "${C_CYAN}--- Delete Tunnel ---${C_RESET}"
    list_tunnels
    echo ""
    read -p "Enter Local Port or PID to terminate (or 'all' to kill everything): " target < /dev/tty
    if [[ "$target" == "all" ]]; then
        pkill -f "ssh.*${REMOTE_HOST}"
        > "$DB_FILE"
        echo -e "${C_GREEN}All tunnels terminated.${C_RESET}"
        return
    fi
    local TMP=$(mktemp)
    local found=0
    while IFS=: read -r LPORT RPORT PID; do
        if [[ "$LPORT" == "$target" || "$PID" == "$target" ]]; then
            kill "$PID" 2>/dev/null
            echo -e "${C_GREEN}[SUCCESS] Terminated tunnel for port $LPORT.${C_RESET}"
            ((found++))
        else
            echo "$LPORT:$RPORT:$PID" >> "$TMP"
        fi
    done < "$DB_FILE"
    mv "$TMP" "$DB_FILE"
    [[ $found -eq 0 ]] && echo -e "${C_RED}Error: Port or PID '$target' not found.${C_RESET}"
}

setup_vps() {
    echo -e "${C_CYAN}--- VPS Initial Setup ---${C_RESET}"
    echo -e "${C_YELLOW}Connecting to ${REMOTE_HOST} to FORCE GatewayPorts...${C_RESET}"
    
    # -q hides MOTD/login banner, -p "" hides sudo prompt
    if sshpass -p '@rey1234' ssh -q -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
        echo '@rey1234' | sudo -S -p "" bash -c "
            sed -i '/^GatewayPorts/d' /etc/ssh/sshd_config
            echo 'GatewayPorts yes' >> /etc/ssh/sshd_config
            sed -i '/^AllowTcpForwarding/d' /etc/ssh/sshd_config
            echo 'AllowTcpForwarding yes' >> /etc/ssh/sshd_config
            systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
            ufw disable 2>/dev/null || iptables -F 2>/dev/null
        "
EOF
    then
        echo -e "${C_GREEN}[SUCCESS] VPS Configured Successfully! (GatewayPorts Enforced)${C_RESET}"
    else
        echo -e "${C_RED}[FAILED] Connection failed or Permission Denied. Check VPS status.${C_RESET}"
    fi
}

check_dependencies

while true; do
    print_header
    echo -e "${C_WHITE}1.${C_RESET} Create a New Tunnel"
    echo -e "${C_WHITE}2.${C_RESET} List Active Tunnels"
    echo -e "${C_WHITE}3.${C_RESET} Delete / Kill a Tunnel"
    echo -e "${C_WHITE}4.${C_RESET} Setup VPS ${C_RED}(Run this once if not done yet)${C_RESET}"
    echo -e "${C_WHITE}5.${C_RESET} Exit"
    echo ""
    read -p "Select an option [1-5]: " choice < /dev/tty

    echo ""
    case $choice in
        1) create_tunnel; pause ;;
        2) list_tunnels; pause ;;
        3) delete_tunnel; pause ;;
        4) setup_vps; pause ;;
        5) echo -e "${C_GREEN}Exiting Tunnelsmith. Goodbye!${C_RESET}"; exit 0 ;;
        *) echo -e "${C_RED}Invalid option.${C_RESET}"; sleep 1 ;;
    esac
done
