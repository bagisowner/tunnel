#!/usr/bin/env bash

# ==============================================================================
# Dynamic Port Forwarding Manager (Interactive Menu)
# VPS Endpoint: 103.165.11.123
# ==============================================================================

VPS_USER="root"
VPS_HOST="103.165.11.123"
SSH_PORT="22"

# Colors for professional UI
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

get_random_port() {
    shuf -i 10000-65000 -n 1
}

check_dependencies() {
    for cmd in ssh socat; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}[-] Missing dependency: '$cmd'. Please install it first.${NC}"
            exit 1
        fi
    done
}

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "=========================================================="
    echo "         FORWARDING TUNNEL MANAGER (IPv4 RELAY)           "
    echo "                 Host: $VPS_HOST                          "
    echo "=========================================================="
    echo -e "${NC}"
}

start_tunnel() {
    local local_port="$1"
    local proto="$2"
    local remote_port=$(get_random_port)

    echo ""
    echo -e "${YELLOW}[*] Initializing $proto tunnel for local port : $local_port...${NC}"

    case "$proto" in
        TCP)
            echo -e "${GREEN}${BOLD}[✔] Tunnel Active!${NC}"
            echo -e "Public Address: ${CYAN}${BOLD}$VPS_HOST:$remote_port${NC} -> ${BOLD}localhost:$local_port (TCP)${NC}"
            echo -e "${YELLOW}[!] Press Ctrl+C anytime to stop and destroy the route.${NC}\n"

            ssh -N -R "0.0.0.0:${remote_port}:localhost:${local_port}" \
                -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}"
            ;;

        UDP)
            socat TCP-LISTEN:"$remote_port",bind=127.0.0.1,reuseaddr,fork UDP:127.0.0.1:"$local_port" &
            LOCAL_SOCAT_PID=$!

            ssh -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" \
                "nohup socat UDP-LISTEN:${remote_port},fork,reuseaddr TCP:127.0.0.1:${remote_port} >/dev/null 2>&1 & echo \$!" > /tmp/remote_socat.pid

            trap 'kill $LOCAL_SOCAT_PID 2>/dev/null; ssh -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" "kill \$(cat /tmp/remote_socat.pid) 2>/dev/null"; rm -f /tmp/remote_socat.pid; echo -e "\n${RED}[-] Tunnel closed.${NC}"; exit' INT TERM

            echo -e "${GREEN}${BOLD}[✔] UDP Tunnel Active!${NC}"
            echo -e "Public Address: ${CYAN}${BOLD}$VPS_HOST:$remote_port${NC} -> ${BOLD}localhost:$local_port (UDP)${NC}"
            echo -e "${YELLOW}[!] Press Ctrl+C anytime to stop and destroy the route.${NC}\n"

            ssh -N -R "127.0.0.1:${remote_port}:127.0.0.1:${remote_port}" \
                -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}"
            ;;

        BOTH)
            socat TCP-LISTEN:"$remote_port",bind=127.0.0.1,reuseaddr,fork UDP:127.0.0.1:"$local_port" &
            LOCAL_SOCAT_PID=$!

            ssh -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" \
                "nohup socat UDP-LISTEN:${remote_port},fork,reuseaddr TCP:127.0.0.1:${remote_port} >/dev/null 2>&1 & echo \$!" > /tmp/remote_socat.pid

            trap 'kill $LOCAL_SOCAT_PID 2>/dev/null; ssh -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" "kill \$(cat /tmp/remote_socat.pid) 2>/dev/null"; rm -f /tmp/remote_socat.pid; echo -e "\n${RED}[-] Tunnel closed.${NC}"; exit' INT TERM

            echo -e "${GREEN}${BOLD}[✔] Dual TCP+UDP Tunnel Active!${NC}"
            echo -e "Public Address: ${CYAN}${BOLD}$VPS_HOST:$remote_port${NC} -> ${BOLD}localhost:$local_port (TCP+UDP)${NC}"
            echo -e "${YELLOW}[!] Press Ctrl+C anytime to stop and destroy the route.${NC}\n"

            ssh -N \
                -R "0.0.0.0:${remote_port}:localhost:${local_port}" \
                -R "127.0.0.1:${remote_port}:127.0.0.1:${remote_port}" \
                -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}"
            ;;
    esac
}

main_menu() {
    check_dependencies
    while true; do
        print_header
        echo " Select an option:"
        echo " -----------------"
        echo " [1] Forward SSH (Local Port 22 - TCP)"
        echo " [2] Forward HTTPS / Web (Local Port 443 - TCP)"
        echo " [3] Forward Custom TCP Port"
        echo " [4] Forward Custom UDP Port"
        echo " [5] Forward Custom Dual TCP + UDP Port"
        echo " [6] Test VPS Connection"
        echo " [0] Exit"
        echo ""
        read -rp "Enter choice [0-6]: " choice

        case "$choice" in
            1)
                start_tunnel "22" "TCP"
                ;;
            2)
                start_tunnel "443" "TCP"
                ;;
            3)
                read -rp "Enter target local TCP port: " lport
                [[ "$lport" =~ ^[0-9]+$ ]] && start_tunnel "$lport" "TCP" || echo -e "${RED}Invalid port number.${NC}"
                ;;
            4)
                read -rp "Enter target local UDP port: " lport
                [[ "$lport" =~ ^[0-9]+$ ]] && start_tunnel "$lport" "UDP" || echo -e "${RED}Invalid port number.${NC}"
                ;;
            5)
                read -rp "Enter target local port for TCP+UDP: " lport
                [[ "$lport" =~ ^[0-9]+$ ]] && start_tunnel "$lport" "BOTH" || echo -e "${RED}Invalid port number.${NC}"
                ;;
            6)
                echo -e "\n${YELLOW}[*] Testing connection to ${VPS_HOST}...${NC}"
                if ssh -q -o BatchMode=yes -o ConnectTimeout=5 "${VPS_USER}@${VPS_HOST}" exit 2>/dev/null; then
                    echo -e "${GREEN}[✔] SSH Authentication & Connection Successful!${NC}"
                else
                    echo -e "${RED}[✘] Connection failed. Make sure your SSH key is added: ssh-copy-id ${VPS_USER}@${VPS_HOST}${NC}"
                fi
                read -rp "Press Enter to return to menu..."
                ;;
            0)
                echo -e "\n${CYAN}Exiting.${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}Invalid option selected.${NC}"
                sleep 1
                ;;
        esac
    done
}

main_menu
