#!/bin/bash

#==============================================================================#
#                                                                              #
#                                 🚇 Tunnelsmith 🚇                              #
#           A cool and friendly script for creating reverse SSH tunnels.       #
#                                                                              #
#==============================================================================#

# --- Configuration (UPDATED FOR YOUR VPS) ---
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

EMOJI_TUNNEL="🚇"
EMOJI_SPARKLE="✨"
EMOJI_GEAR="⚙️"
EMOJI_LINK="🔗"
EMOJI_SUCCESS="✅"
EMOJI_ERROR="❌"
EMOJI_STOP="🛑"
EMOJI_LIST="📋"
EMOJI_WAVE="👋"

# --- Helper Functions ---
usage() {
    echo -e "${C_WHITE}🚇 Tunnelsmith - a friendly tunnel manager${C_RESET}"
    echo -e "---------------------------------------------------"
    echo -e "${C_YELLOW}Usage:${C_RESET} ${C_CYAN}$0 ${C_PURPLE}<command> [options]${C_RESET}\n"
    echo -e "${C_PURPLE}Commands:${C_RESET}"
    echo -e "  ${C_CYAN}make <local_port>${C_RESET}   ${EMOJI_GEAR} Create a new tunnel from a local port."
    echo -e "                         Example: ${C_CYAN}$0 make 8080${C_RESET}\n"
    echo -e "  ${C_CYAN}list${C_RESET}                ${EMOJI_LIST} List all active tunnels.\n"
    echo -e "  ${C_CYAN}kill <pid>${C_RESET}          ${EMOJI_STOP} Stop a specific tunnel by its PID."
    echo -e "                         Example: ${C_CYAN}$0 kill 12345${C_RESET}\n"
    echo -e "  ${C_CYAN}killall${C_RESET}             ${EMOJI_STOP} Stop all active tunnels.\n"
    echo -e "  ${C_CYAN}help${C_RESET}                ${EMOJI_WAVE} Show this help message."
    echo -e "---------------------------------------------------"
}

# --- Check sshpass ---
if ! command -v sshpass &> /dev/null; then
    echo -e "${EMOJI_ERROR} ${C_RED}Error: 'sshpass' is required but not installed.${C_RESET}"
    echo -e "${C_YELLOW}Please install it using: sudo apt install sshpass -y (or pkg install sshpass)${C_RESET}"
    exit 1
fi

# --- Main Logic ---
if [ -z "$1" ]; then
    usage
    exit 1
fi

case "$1" in
    make)
        LOCAL_PORT=$2
        if [[ -z "$LOCAL_PORT" || ! "$LOCAL_PORT" =~ ^[0-9]+$ ]]; then
            echo -e "\n${EMOJI_ERROR} ${C_RED}Error: You must provide a valid local port number.${C_RESET}"
            echo -e "Example: ${C_CYAN}$0 make 80${C_RESET}\n"
            exit 1
        fi

        REMOTE_PORT=$(( RANDOM % 55535 + 10000 ))

        echo -e "\n${EMOJI_TUNNEL} ${C_BLUE}Forging a new tunnel...${C_RESET}"
        echo -e "${EMOJI_GEAR} ${C_YELLOW}Preparing to connect to ${C_WHITE}${REMOTE_HOST}${C_RESET}"
        echo -e "${EMOJI_LINK} ${C_CYAN}Forwarding:${C_RESET} Local Port ${C_WHITE}${LOCAL_PORT}${C_RESET} -> ${C_WHITE}${REMOTE_HOST}:${REMOTE_PORT}${C_RESET}\n"

        # Automated login with sshpass and 0.0.0.0 for public access
        nohup sshpass -p "${VPS_PASS}" ssh -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes -o ServerAliveInterval=60 \
            -N -R 0.0.0.0:${REMOTE_PORT}:localhost:${LOCAL_PORT} \
            ${REMOTE_USER}@${REMOTE_HOST} -p ${SSH_PORT} &> /tmp/tunnel_${REMOTE_PORT}.log &

        PID=$!
        sleep 2

        if ps -p $PID > /dev/null; then
            echo -e "${EMOJI_SUCCESS} ${C_GREEN}Success! Tunnel is active.${C_RESET}"
            echo -e "  ${C_WHITE}PID:${C_RESET} ${C_YELLOW}${PID}${C_RESET}"
            echo -e "  ${C_WHITE}Connect:${C_RESET} ${C_PURPLE}ssh <user>@${REMOTE_HOST} -p ${REMOTE_PORT}${C_RESET} (For SSH)"
            echo -e "  ${C_WHITE}URL:${C_RESET} ${C_CYAN}http://${REMOTE_HOST}:${REMOTE_PORT}${C_RESET} (For Web)"
            echo -e "  ${C_WHITE}Log:${C_RESET} /tmp/tunnel_${REMOTE_PORT}.log"
            echo -e "\n${EMOJI_STOP} To stop this tunnel, run: ${C_PURPLE}$0 kill ${PID}${C_RESET}\n"
            echo -e "${C_RED}[!] NOTE: Ensure Port $REMOTE_PORT is OPEN in your VPS Panel!${C_RESET}"
        else
            echo -e "${EMOJI_ERROR} ${C_RED}Oh no! The tunnel failed to start.${C_RESET}"
            echo -e "  Check the log for details: ${C_YELLOW}cat /tmp/tunnel_${REMOTE_PORT}.log${C_RESET}\n"
            [ ! -s "/tmp/tunnel_${REMOTE_PORT}.log" ] && rm "/tmp/tunnel_${REMOTE_PORT}.log"
        fi
        ;;

    list)
        echo -e "\n${EMOJI_LIST} ${C_BLUE}Searching for active tunnels to ${C_WHITE}${REMOTE_HOST}${C_RESET}..."
        PIDS=$(pgrep -af "ssh.*-R.*${REMOTE_HOST}")
        
        if [ -n "$PIDS" ]; then
            echo -e "------------------------------------------------------------------"
            echo -e "${C_WHITE}PID\t\tREMOTE PORT\t\tFORWARDED FROM (Local Port)${C_RESET}"
            echo -e "------------------------------------------------------------------"
            while read -r line; do
                pid=$(echo "$line" | awk '{print $1}')
                remote_p=$(echo "$line" | sed -n 's/.*-R 0.0.0.0:\([0-9]*\):.*/\1/p')
                local_p=$(echo "$line" | sed -n 's/.*localhost:\([0-9]*\).*/\1/p')
                echo -e "${C_YELLOW}${pid}${C_RESET}\t\t${C_CYAN}${remote_p}${C_RESET}\t\t\t${C_PURPLE}${local_p}${C_RESET}"
            done <<< "$PIDS"
            echo -e "------------------------------------------------------------------\n"
        else
            echo -e "${EMOJI_SPARKLE} ${C_GREEN}No active tunnels found. Your network is quiet!${C_RESET}\n"
        fi
        ;;

    kill)
        PID_TO_KILL=$2
        if [[ -z "$PID_TO_KILL" || ! "$PID_TO_KILL" =~ ^[0-9]+$ ]]; then
            echo -e "\n${EMOJI_ERROR} ${C_RED}Error: You must provide a valid PID to kill.${C_RESET}"
            exit 1
        fi
        if ps -p $PID_TO_KILL > /dev/null; then
            kill $PID_TO_KILL
            echo -e "\n${EMOJI_STOP} ${C_GREEN}Signal sent to terminate tunnel with PID ${C_YELLOW}${PID_TO_KILL}${C_RESET}.${C_RESET}\n"
        else
            echo -e "\n${EMOJI_ERROR} ${C_RED}Error: No process found with PID ${C_YELLOW}${PID_TO_KILL}${C_RESET}.${C_RESET}\n"
        fi
        ;;

    killall)
        echo -e "\n${EMOJI_STOP} ${C_BLUE}Preparing to terminate all tunnels to ${C_WHITE}${REMOTE_HOST}${C_RESET}..."
        PIDS_TO_KILL=$(pgrep -f "ssh.*-R.*${REMOTE_HOST}")
        
        if [ -n "$PIDS_TO_KILL" ]; then
            echo -e "${C_YELLOW}This will kill the following processes:${C_RESET}"
            pgrep -af "ssh.*-R.*${REMOTE_HOST}"
            read -p "$(echo -e ${C_RED}"Are you sure? [y/N] "${C_RESET})" confirm
            if [[ "$confirm" =~ ^[yY](es)?$ ]]; then
                kill $PIDS_TO_KILL
                echo -e "\n${EMOJI_SUCCESS} ${C_GREEN}All tunnels terminated.${C_RESET}\n"
            fi
        else
            echo -e "${EMOJI_SPARKLE} ${C_GREEN}No active tunnels to kill.${C_RESET}\n"
        fi
        ;;

    help|*)
        usage
        ;;
esac
