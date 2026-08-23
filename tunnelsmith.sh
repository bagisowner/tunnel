#!/usr/bin/env bash

# ==============================================================================
# Dynamic Port Forwarding Manager (Background Daemon + Process Control)
# VPS Endpoint: 103.165.11.123
# ==============================================================================

VPS_USER="root"
VPS_HOST="103.165.11.123"
SSH_PORT="22"

STATE_DIR="$HOME/.tunnel_manager"
STATE_FILE="$STATE_DIR/active_tunnels.db"
mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

# Colors for UI
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
    for cmd in ssh socat awk; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}[-] Missing dependency: '$cmd'. Please install it first.${NC}"
            exit 1
        fi
    done
}

# Clean dead processes from database
sync_tunnels() {
    local tmp_file="$STATE_DIR/tmp_db"
    > "$tmp_file"
    while IFS="|" read -r id proto lport rport ssh_pid local_socat_pid remote_socat_pid; do
        if kill -0 "$ssh_pid" 2>/dev/null; then
            echo "$id|$proto|$lport|$rport|$ssh_pid|$local_socat_pid|$remote_socat_pid" >> "$tmp_file"
        fi
    done < "$STATE_FILE"
    mv "$tmp_file" "$STATE_FILE"
}

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "=========================================================="
    echo "         FORWARDING TUNNEL MANAGER (DAEMON MODE)          "
    echo "                 Host: $VPS_HOST                          "
    echo "=========================================================="
    echo -e "${NC}"
}

spawn_tunnel() {
    local local_port="$1"
    local proto="$2"
    local remote_port=$(get_random_port)
    local tunnel_id=$(date +%s%N | cut -b10-14)

    echo -e "\n${YELLOW}[*] Spawning $proto tunnel in background...${NC}"

    case "$proto" in
        TCP)
            ssh -f -N -R "0.0.0.0:${remote_port}:localhost:${local_port}" \
                -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}"
            
            # Retrieve spawned SSH PID
            SSH_PID=$(pgrep -f "ssh -f -N -R 0.0.0.0:${remote_port}:localhost:${local_port}" | tail -n 1)

            echo "$tunnel_id|TCP|$local_port|$remote_port|$SSH_PID|NONE|NONE" >> "$STATE_FILE"
            ;;

        UDP)
            socat TCP-LISTEN:"$remote_port",bind=127.0.0.1,reuseaddr,fork UDP:127.0.0.1:"$local_port" &
            LOCAL_SOCAT_PID=$!

            REMOTE_SOCAT_PID=$(ssh -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" \
                "nohup socat UDP-LISTEN:${remote_port},fork,reuseaddr TCP:127.0.0.1:${remote_port} >/dev/null 2>&1 & echo \$!")

            ssh -f -N -R "127.0.0.1:${remote_port}:127.0.0.1:${remote_port}" \
                -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}"

            SSH_PID=$(pgrep -f "ssh -f -N -R 127.0.0.1:${remote_port}:127.0.0.1:${remote_port}" | tail -n 1)

            echo "$tunnel_id|UDP|$local_port|$remote_port|$SSH_PID|$LOCAL_SOCAT_PID|$REMOTE_SOCAT_PID" >> "$STATE_FILE"
            ;;

        BOTH)
            socat TCP-LISTEN:"$remote_port",bind=127.0.0.1,reuseaddr,fork UDP:127.0.0.1:"$local_port" &
            LOCAL_SOCAT_PID=$!

            REMOTE_SOCAT_PID=$(ssh -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" \
                "nohup socat UDP-LISTEN:${remote_port},fork,reuseaddr TCP:127.0.0.1:${remote_port} >/dev/null 2>&1 & echo \$!")

            ssh -f -N \
                -R "0.0.0.0:${remote_port}:localhost:${local_port}" \
                -R "127.0.0.1:${remote_port}:127.0.0.1:${remote_port}" \
                -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}"

            SSH_PID=$(pgrep -f "0.0.0.0:${remote_port}:localhost:${local_port}" | tail -n 1)

            echo "$tunnel_id|BOTH|$local_port|$remote_port|$SSH_PID|$LOCAL_SOCAT_PID|$REMOTE_SOCAT_PID" >> "$STATE_FILE"
            ;;
    esac

    echo -e "${GREEN}${BOLD}[✔] Tunnel Started in Background!${NC}"
    echo -e "ID         : ${BOLD}$tunnel_id${NC}"
    echo -e "Protocol   : ${BOLD}$proto${NC}"
    echo -e "Local Target: ${BOLD}127.0.0.1:$local_port${NC}"
    echo -e "Public Endpoint: ${CYAN}${BOLD}$VPS_HOST:$remote_port${NC}"
    echo ""
    read -rp "Press Enter to return to menu..."
}

list_and_kill_tunnels() {
    sync_tunnels
    while true; do
        print_header
        echo -e "${BOLD}ACTIVE BACKGROUND TUNNELS:${NC}"
        echo "----------------------------------------------------------------------------------"
        printf "%-8s %-8s %-12s %-28s %-8s\n" "ID" "PROTO" "LOCAL PORT" "PUBLIC ENDPOINT" "PID"
        echo "----------------------------------------------------------------------------------"

        if [ ! -s "$STATE_FILE" ]; then
            echo -e "${YELLOW}No active tunnels running.${NC}"
            echo "----------------------------------------------------------------------------------"
            echo ""
            read -rp "Press Enter to return to main menu..."
            break
        fi

        while IFS="|" read -r id proto lport rport ssh_pid local_socat_pid remote_socat_pid; do
            printf "%-8s %-8s %-12s %-28s %-8s\n" "$id" "$proto" "$lport" "$VPS_HOST:$rport" "$ssh_pid"
        done < "$STATE_FILE"

        echo "----------------------------------------------------------------------------------"
        echo ""
        echo "Options: Enter [ID] to terminate tunnel | [all] to stop all | [0] Back to Main Menu"
        read -rp "Action: " act

        if [ "$act" = "0" ] || [ -z "$act" ]; then
            break
        elif [ "$act" = "all" ]; then
            while IFS="|" read -r id proto lport rport ssh_pid local_socat_pid remote_socat_pid; do
                kill "$ssh_pid" 2>/dev/null
                [ "$local_socat_pid" != "NONE" ] && kill "$local_socat_pid" 2>/dev/null
                [ "$remote_socat_pid" != "NONE" ] && ssh -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" "kill $remote_socat_pid 2>/dev/null"
            done < "$STATE_FILE"
            > "$STATE_FILE"
            echo -e "${RED}[✔] All background tunnels terminated.${NC}"
            sleep 1
            break
        else
            matched_line=$(grep "^$act|" "$STATE_FILE")
            if [ -n "$matched_line" ]; then
                IFS="|" read -r id proto lport rport ssh_pid local_socat_pid remote_socat_pid <<< "$matched_line"
                kill "$ssh_pid" 2>/dev/null
                [ "$local_socat_pid" != "NONE" ] && kill "$local_socat_pid" 2>/dev/null
                [ "$remote_socat_pid" != "NONE" ] && ssh -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" "kill $remote_socat_pid 2>/dev/null"
                
                grep -v "^$act|" "$STATE_FILE" > "$STATE_DIR/tmp" && mv "$STATE_DIR/tmp" "$STATE_FILE"
                echo -e "${GREEN}[✔] Successfully terminated tunnel $act.${NC}"
                sleep 1
            else
                echo -e "${RED}[✘] Invalid Tunnel ID.${NC}"
                sleep 1
            fi
        fi
    done
}

main_menu() {
    check_dependencies
    while true; do
        sync_tunnels
        active_count=$(wc -l < "$STATE_FILE" | tr -d ' ')
        
        print_header
        echo -e " Active Background Tunnels: ${GREEN}${BOLD}$active_count${NC}"
        echo " ---------------------------------------------------------"
        echo " [1] Forward SSH (Local Port 22 - TCP)"
        echo " [2] Forward HTTPS / Web (Local Port 443 - TCP)"
        echo " [3] Forward Custom TCP Port"
        echo " [4] Forward Custom UDP Port"
        echo " [5] Forward Custom Dual TCP + UDP Port"
        echo " [6] View Running Ports / Kill Background Tunnels"
        echo " [7] Test VPS Connection"
        echo " [0] Exit"
        echo ""
        read -rp "Enter choice [0-7]: " choice

        case "$choice" in
            1)
                spawn_tunnel "22" "TCP"
                ;;
            2)
                spawn_tunnel "443" "TCP"
                ;;
            3)
                read -rp "Enter target local TCP port: " lport
                [[ "$lport" =~ ^[0-9]+$ ]] && spawn_tunnel "$lport" "TCP" || echo -e "${RED}Invalid port.${NC}"
                ;;
            4)
                read -rp "Enter target local UDP port: " lport
                [[ "$lport" =~ ^[0-9]+$ ]] && spawn_tunnel "$lport" "UDP" || echo -e "${RED}Invalid port.${NC}"
                ;;
            5)
                read -rp "Enter target local port for TCP+UDP: " lport
                [[ "$lport" =~ ^[0-9]+$ ]] && spawn_tunnel "$lport" "BOTH" || echo -e "${RED}Invalid port.${NC}"
                ;;
            6)
                list_and_kill_tunnels
                ;;
            7)
                echo -e "\n${YELLOW}[*] Testing connection to ${VPS_HOST}...${NC}"
                if ssh -q -o BatchMode=yes -o ConnectTimeout=5 "${VPS_USER}@${VPS_HOST}" exit 2>/dev/null; then
                    echo -e "${GREEN}[✔] SSH Connection Successful!${NC}"
                else
                    echo -e "${RED}[✘] Connection failed. Run: ssh-copy-id ${VPS_USER}@${VPS_HOST}${NC}"
                fi
                read -rp "Press Enter to return to menu..."
                ;;
            0)
                echo -e "\n${CYAN}Exiting CLI (Background tunnels remain running).${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}Invalid selection.${NC}"
                sleep 1
                ;;
        esac
    done
}

main_menu
