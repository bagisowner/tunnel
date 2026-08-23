#!/bin/bash

#==============================================================================#
#                                                                              #
#                                 🚇 Tunnelsmith 🚇                              #
#                 Professional Menu-Driven SSH Tunnel Manager                  #
#                                                                              #
#==============================================================================#

# --- Configuration ---
REMOTE_HOST="103.165.11.123"
REMOTE_USER="root"
SSH_PORT="22"
VPS_PASS="123rey"

# --- Colors and Emojis ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_PURPLE='\033[0;35m'
C_CYAN='\033[0;36m'
C_WHITE='\033[1;37m'
C_BOLD='\033[1m'

EMOJI_TUNNEL="🚇"
EMOJI_SPARKLE="✨"
EMOJI_GEAR="⚙️"
EMOJI_LINK="🔗"
EMOJI_SUCCESS="✅"
EMOJI_ERROR="❌"
EMOJI_STOP="🛑"
EMOJI_LIST="📋"
EMOJI_BOMB="💥"
EMOJI_WAVE="👋"

# --- Dependency Check ---
check_dependencies() {
    if ! command -v sshpass &> /dev/null; then
        clear
        echo -e "${EMOJI_GEAR} ${C_YELLOW}Checking dependencies...${C_RESET}"
        echo -e "${EMOJI_ERROR} ${C_RED}'sshpass' is required but not installed.${C_RESET}"
        
        if command -v pkg &> /dev/null; then
            echo -e "${C_CYAN}Installing via pkg (Termux)...${C_RESET}"
            pkg update -y && pkg install sshpass -y
        elif command -v apt-get &> /dev/null; then
            echo -e "${C_CYAN}Installing via apt...${C_RESET}"
            sudo apt-get update -y && sudo apt-get install sshpass -y
        else
            echo -e "${C_RED}Please install 'sshpass' manually to continue.${C_RESET}"
            exit 1
        fi
        sleep 2
    fi
}

# --- UI Functions ---
print_header() {
    clear
    echo -e "${C_CYAN}${C_BOLD}"
    echo "  _____                     _               _ _   _     "
    echo " |_   _|   _ _ __  _ __   ___| |___ _ __ ___(_) |_| |__  "
    echo "   | || | | | '_ \| '_ \ / _ \ / __| '_ \` _ \ | __| '_ \ "
    echo "   | || |_| | | | | | | |  __/ \__ \ | | | | | | |_| | | |"
    echo "   |_| \__,_|_| |_|_| |_|\___|_|___/_| |_| |_|_|\__|_| |_|"
    echo -e "${C_RESET}"
    echo -e "${C_WHITE}           ${EMOJI_TUNNEL} Target Server: ${C_YELLOW}${REMOTE_HOST}${C_RESET}"
    echo -e "${C_PURPLE}==============================================================${C_RESET}\n"
}

pause() {
    echo -e "\n${C_WHITE}Press [ENTER] to return to the menu...${C_RESET}"
    read -r < /dev/tty
}

# --- Core Features ---
create_tunnel() {
    echo -e "${C_CYAN}--- ${EMOJI_GEAR} Create New Tunnel ---${C_RESET}"
    read -p "Enter LOCAL Port to forward (e.g., 8080, 22): " LOCAL_PORT < /dev/tty
    read -p "Enter REMOTE Port for VPS (e.g., 2222, 9090): " REMOTE_PORT < /dev/tty

    if [[ ! "$LOCAL_PORT" =~ ^[0-9]+$ ]] || [[ ! "$REMOTE_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${EMOJI_ERROR} ${C_RED}Error: Invalid port numbers.${C_RESET}"
        return 1
    fi

    echo -e "\n${EMOJI_TUNNEL} ${C_BLUE}Forging a secure tunnel to ${REMOTE_HOST}...${C_RESET}"
    
    # Run the tunnel in background
    nohup sshpass -p "${VPS_PASS}" ssh -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes -o ServerAliveInterval=60 \
        -N -R 0.0.0.0:${REMOTE_PORT}:localhost:${LOCAL_PORT} \
        ${REMOTE_USER}@${REMOTE_HOST} -p ${SSH_PORT} &> /tmp/tunnel_${REMOTE_PORT}.log &

    local PID=$!
    sleep 2 # Wait to see if it crashes instantly

    if ps -p $PID > /dev/null 2>&1; then
        echo -e "${EMOJI_SUCCESS} ${C_GREEN}Success! Tunnel is LIVE.${C_RESET}"
        echo -e "---------------------------------------------------"
        echo -e " ${EMOJI_GEAR} Process ID   : ${C_YELLOW}${PID}${C_RESET}"
        echo -e " ${EMOJI_LINK} Forwarding   : ${C_PURPLE}localhost:${LOCAL_PORT}${C_RESET} ➔ ${C_CYAN}${REMOTE_HOST}:${REMOTE_PORT}${C_RESET}"
        echo -e " 💻 SSH Command  : ${C_WHITE}ssh <user>@${REMOTE_HOST} -p ${REMOTE_PORT}${C_RESET}"
        echo -e " 🌐 Web URL      : ${C_WHITE}http://${REMOTE_HOST}:${REMOTE_PORT}${C_RESET}"
        echo -e "---------------------------------------------------"
        echo -e "${C_RED}[!] Make sure Port $REMOTE_PORT is OPEN in your VPS Dashboard/Firewall!${C_RESET}"
    else
        echo -e "${EMOJI_ERROR} ${C_RED}Failed to establish tunnel.${C_RESET}"
        echo -e "Debug Log:"
        cat "/tmp/tunnel_${REMOTE_PORT}.log"
        [ ! -s "/tmp/tunnel_${REMOTE_PORT}.log" ] && rm "/tmp/tunnel_${REMOTE_PORT}.log"
    fi
}

list_tunnels() {
    echo -e "${C_CYAN}--- ${EMOJI_LIST} Active Tunnels ---${C_RESET}"
    local PIDS=$(pgrep -af "ssh.*-R.*${REMOTE_HOST}")
    
    if [ -n "$PIDS" ]; then
        printf "${C_WHITE}%-10s | %-15s | %-15s${C_RESET}\n" "PID" "REMOTE PORT" "LOCAL PORT"
        echo -e "${C_PURPLE}---------------------------------------------------${C_RESET}"
        while read -r line; do
            local pid=$(echo "$line" | awk '{print $1}')
            local remote_p=$(echo "$line" | sed -n 's/.*-R 0.0.0.0:\([0-9]*\):.*/\1/p')
            local local_p=$(echo "$line" | sed -n 's/.*localhost:\([0-9]*\).*/\1/p')
            printf "${C_YELLOW}%-10s${C_RESET} | ${C_CYAN}%-15s${C_RESET} | ${C_PURPLE}%-15s${C_RESET}\n" "$pid" "$remote_p" "$local_p"
        done <<< "$PIDS"
        echo -e "${C_PURPLE}---------------------------------------------------${C_RESET}"
    else
        echo -e "${EMOJI_SPARKLE} ${C_GREEN}No active tunnels running.${C_RESET}"
    fi
}

kill_tunnel() {
    echo -e "${C_CYAN}--- ${EMOJI_STOP} Terminate Tunnel ---${C_RESET}"
    list_tunnels
    echo ""
    read -p "Enter the PID of the tunnel to stop: " target_pid < /dev/tty
    
    if [[ ! "$target_pid" =~ ^[0-9]+$ ]]; then
        echo -e "${EMOJI_ERROR} ${C_RED}Invalid PID format.${C_RESET}"
        return
    fi

    if ps -p "$target_pid" > /dev/null 2>&1; then
        kill "$target_pid"
        echo -e "${EMOJI_SUCCESS} ${C_GREEN}Tunnel with PID ${target_pid} terminated.${C_RESET}"
    else
        echo -e "${EMOJI_ERROR} ${C_RED}No active process found with PID ${target_pid}.${C_RESET}"
    fi
}

kill_all() {
    echo -e "${C_CYAN}--- ${EMOJI_BOMB} Terminate ALL Tunnels ---${C_RESET}"
    local PIDS_TO_KILL=$(pgrep -f "ssh.*-R.*${REMOTE_HOST}")
    
    if [ -n "$PIDS_TO_KILL" ]; then
        read -p "$(echo -e ${C_RED}"Are you sure you want to kill ALL tunnels? (y/N): "${C_RESET})" confirm < /dev/tty
        if [[ "$confirm" =~ ^[yY](es)?$ ]]; then
            kill $PIDS_TO_KILL
            echo -e "${EMOJI_SUCCESS} ${C_GREEN}All tunnels have been cleared!${C_RESET}"
        else
            echo -e "${C_YELLOW}Operation cancelled.${C_RESET}"
        fi
    else
        echo -e "${EMOJI_SPARKLE} ${C_GREEN}No active tunnels to kill.${C_RESET}"
    fi
}

# --- Initialization ---
check_dependencies

# --- Main Menu Loop ---
while true; do
    print_header
    echo -e "${C_WHITE}1.${C_RESET} ${EMOJI_GEAR} Create a New Tunnel"
    echo -e "${C_WHITE}2.${C_RESET} ${EMOJI_LIST} List Active Tunnels"
    echo -e "${C_WHITE}3.${C_RESET} ${EMOJI_STOP} Stop a Specific Tunnel"
    echo -e "${C_WHITE}4.${C_RESET} ${EMOJI_BOMB} Kill ALL Tunnels"
    echo -e "${C_WHITE}5.${C_RESET} ${EMOJI_WAVE} Exit"
    echo ""
    read -p "Select an option [1-5]: " choice < /dev/tty

    echo ""
    case $choice in
        1) create_tunnel; pause ;;
        2) list_tunnels; pause ;;
        3) kill_tunnel; pause ;;
        4) kill_all; pause ;;
        5) echo -e "${EMOJI_WAVE} ${C_GREEN}Exiting Tunnelsmith. Goodbye!${C_RESET}"; exit 0 ;;
        *) echo -e "${EMOJI_ERROR} ${C_RED}Invalid choice. Try again.${C_RESET}"; sleep 1 ;;
    esac
done
