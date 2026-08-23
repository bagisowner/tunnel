#!/bin/bash

#==============================================================================#
#                           UNIVERSAL TUNNELSMITH                              #
#                      Professional SSH Tunnel Manager                         #
#==============================================================================#

# --- Configuration ---
REMOTE_HOST="103.165.11.161"
REMOTE_USER="root1"
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

# Ensure Database Exists
mkdir -p /tmp
touch "$DB_FILE"

# --- Helper Functions ---
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

# --- Core Features ---
create_tunnel() {
    echo -e "${C_CYAN}--- Create New Tunnel ---${C_RESET}"
    read -p "Enter the Local Port to forward: " LOCAL_PORT < /dev/tty

    if [[ ! "$LOCAL_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${C_RED}Error: Invalid port number.${C_RESET}"
        return 1
    fi

    echo -e "${C_YELLOW}Establishing secure connection to ${REMOTE_HOST}...${C_RESET}"
    
    local TMP_LOG=$(mktemp)
    
    # Background SSH tunnel
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=15 \
        -N -R 0:localhost:$LOCAL_PORT ${REMOTE_USER}@${REMOTE_HOST} -p ${SSH_PORT} >"$TMP_LOG" 2>&1 &
    
    local SSH_PID=$!
    
    # Wait for allocation
    for i in {1..20}; do
        sleep 0.5
        if grep -q "Allocated port" "$TMP_LOG" 2>/dev/null; then break; fi
        if ! ps -p "$SSH_PID" > /dev/null 2>&1; then break; fi
    done
    
    if grep -q "Allocated port" "$TMP_LOG" 2>/dev/null; then
        local REMOTE_PORT=$(grep "Allocated port" "$TMP_LOG" | head -n1 | grep -oE '[0-9]{4,5}')
        echo "$LOCAL_PORT:$REMOTE_PORT:$SSH_PID" >> "$DB_FILE"
        echo -e "\n${C_GREEN}[SUCCESS] Tunnel Established Successfully!${C_RESET}"
        echo -e "---------------------------------------------------"
        echo -e " Forwarded Port : ${C_WHITE}localhost:$LOCAL_PORT${C_RESET}"
        echo -e " Public IP      : ${C_CYAN}${REMOTE_HOST}${C_RESET}"
        echo -e " Public Port    : ${C_CYAN}${REMOTE_PORT}${C_RESET}"
        echo -e " Access URL     : ${C_YELLOW}http://${REMOTE_HOST}:${REMOTE_PORT}${C_RESET}"
        echo -e "---------------------------------------------------"
    else
        echo -e "\n${C_RED}[FAILED] Could not establish tunnel.${C_RESET}"
        echo -e "Debug Log:"
        tail -5 "$TMP_LOG"
        kill "$SSH_PID" 2>/dev/null
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
    echo -e "${C_YELLOW}Connecting to ${REMOTE_HOST} to configure GatewayPorts...${C_RESET}"
    
    sshpass -p 'root' ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
        sed -i 's/#GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
        sed -i 's/#AllowTcpForwarding no/AllowTcpForwarding yes/' /etc/ssh/sshd_config
        systemctl restart ssh
        ufw disable 2>/dev/null || iptables -F
EOF
    echo -e "${C_GREEN}[SUCCESS] VPS Configured Successfully!${C_RESET}"
}

# --- Main Interface Loop ---
while true; do
    print_header
    echo -e "${C_WHITE}1.${C_RESET} Create a New Tunnel"
    echo -e "${C_WHITE}2.${C_RESET} List Active Tunnels"
    echo -e "${C_WHITE}3.${C_RESET} Delete / Kill a Tunnel"
    echo -e "${C_WHITE}4.${C_RESET} Setup VPS ${C_RED}(Run Once)${C_RESET}"
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
        *) echo -e "${C_RED}Invalid option. Please try again.${C_RESET}"; sleep 1 ;;
    esac
done
