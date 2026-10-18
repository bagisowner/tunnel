#!/usr/bin/env bash

# ==============================================================================
# Two-Way Persistent Port Forwarding Manager (VPS 1 <-> VPS 2 Auto-Recovery)
# Survives reboots of EITHER VPS and always reclaims the EXACT same IP:Port
# ==============================================================================

VPS_USER="root"
VPS_HOST="91.226.56.38"
SSH_PORT="22"

STATE_DIR="/etc/tunnel_manager"
# Fallback to $HOME if not running as root
if [ "$(id -u)" -ne 0 ]; then
    STATE_DIR="$HOME/.tunnel_manager"
fi

STATE_FILE="$STATE_DIR/active_tunnels.db"
RUNNER_DIR="$STATE_DIR/runners"
mkdir -p "$STATE_DIR" "$RUNNER_DIR"
touch "$STATE_FILE"

# Colors for UI
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Fast keepalive + strict port forward check so broken tunnels drop & reconnect within seconds
SSH_OPTS="-o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

get_random_port() {
    while true; do
        local port
        port=$(shuf -i 10000-60000 -n 1)
        if ! grep -q "|${port}$" "$STATE_FILE" 2>/dev/null; then
            echo "$port"
            return
        fi
    done
}

check_dependencies() {
    for cmd in ssh socat awk pgrep; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}[-] Missing dependency: '$cmd'. Installing or please install it first...${NC}"
            if command -v apt-get &>/dev/null && [ "$(id -u)" -eq 0 ]; then
                apt-get update -y && apt-get install -y openssh-client socat psmisc lsof
            else
                exit 1
            fi
        fi
    done
}

# Build and start a self-healing runner that handles reboots of BOTH VPS 1 and VPS 2
start_tunnel_processes() {
    local id="$1"
    local proto="$2"
    local lport="$3"
    local rport="$4"
    local relay_port=$((rport + 5000))
    local runner_script="$RUNNER_DIR/tunnel_${id}.sh"

    cat <<EOF > "$runner_script"
#!/usr/bin/env bash
# ==============================================================================
# Auto-Healing Watchdog for Tunnel ID: $id ($proto: Local $lport <-> $VPS_HOST:$rport)
# ==============================================================================

cleanup() {
    pkill -P \$\$ 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# For UDP/BOTH: Keep local UDP-to-TCP bridge alive forever
EOF

    if [ "$proto" = "UDP" ] || [ "$proto" = "BOTH" ]; then
        cat <<EOF >> "$runner_script"
(
    while true; do
        socat TCP-LISTEN:${relay_port},bind=127.0.0.1,reuseaddr,fork UDP:127.0.0.1:${lport} 2>/dev/null
        sleep 2
    done
) &
EOF
    fi

    cat <<EOF >> "$runner_script"
while true; do
    # 1. Wait until Remote VPS ($VPS_HOST) is online and reachable
    if ssh $SSH_OPTS -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" "exit" 2>/dev/null; then

        # 2. Remote Pre-Flight on VPS 2:
        #    - Ensure GatewayPorts is enabled (in case VPS 2 was reset/reinstalled)
        #    - Kill any stale/zombie sshd process holding port ${rport} or ${relay_port}
        #      so VPS 1 can immediately reclaim the EXACT same port after a reboot!
        ssh $SSH_OPTS -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" "bash -s" <<'REMOTE_PREP'
if ! grep -q "^GatewayPorts yes" /etc/ssh/sshd_config 2>/dev/null; then
    sed -i '/^#*GatewayPorts/d' /etc/ssh/sshd_config
    echo "GatewayPorts yes" >> /etc/ssh/sshd_config
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
fi

# Free stale TCP ports held by dead SSH sessions
for p in ${rport} ${relay_port}; do
    fuser -k "\${p}/tcp" >/dev/null 2>&1 || true
    lsof -ti TCP:"\${p}" -sTCP:LISTEN 2>/dev/null | xargs -r kill -9 2>/dev/null || true
done
REMOTE_PREP

EOF

    if [ "$proto" = "UDP" ] || [ "$proto" = "BOTH" ]; then
        cat <<EOF >> "$runner_script"
        # 3. Ensure UDP systemd service exists and is running on VPS 2
        ssh $SSH_OPTS -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" "bash -s" <<'REMOTE_UDP'
if [ ! -f /etc/systemd/system/tunnel_udp_${rport}.service ]; then
cat << 'EOT' > /etc/systemd/system/tunnel_udp_${rport}.service
[Unit]
Description=Socat UDP Tunnel Relay for Public Port ${rport}
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat UDP-LISTEN:${rport},fork,reuseaddr TCP:127.0.0.1:${relay_port}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOT
    systemctl daemon-reload
    systemctl enable tunnel_udp_${rport}.service >/dev/null 2>&1
fi
systemctl start tunnel_udp_${rport}.service 2>/dev/null
REMOTE_UDP
EOF
    fi

    case "$proto" in
        TCP)
            cat <<EOF >> "$runner_script"
        # 4. Lock onto the exact same Public Port (${rport})
        ssh -N -R "0.0.0.0:${rport}:127.0.0.1:${lport}" \\
            $SSH_OPTS -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" 2>/dev/null
EOF
            ;;
        UDP)
            cat <<EOF >> "$runner_script"
        # 4. Lock onto the exact same Relay Port (${relay_port}) for UDP
        ssh -N -R "127.0.0.1:${relay_port}:127.0.0.1:${relay_port}" \\
            $SSH_OPTS -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" 2>/dev/null
EOF
            ;;
        BOTH)
            cat <<EOF >> "$runner_script"
        # 4. Lock onto the exact same Public Port (${rport}) for TCP + UDP Relay
        ssh -N \\
            -R "0.0.0.0:${rport}:127.0.0.1:${lport}" \\
            -R "127.0.0.1:${relay_port}:127.0.0.1:${relay_port}" \\
            $SSH_OPTS -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" 2>/dev/null
EOF
            ;;
    esac

    cat <<EOF >> "$runner_script"
    fi
    sleep 3
done
EOF

    chmod +x "$runner_script"

    # Register local systemd service so when THIS VPS (VPS 1) reboots, it starts automatically on boot
    if [ "$(id -u)" -eq 0 ] && command -v systemctl &>/dev/null && pidof systemd &>/dev/null; then
        cat <<EOF > "/etc/systemd/system/local_tunnel_${id}.service"
[Unit]
Description=Persistent Port Forward Tunnel ${id} (${proto} Local:${lport} -> ${VPS_HOST}:${rport})
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${runner_script}
Restart=always
RestartSec=3
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable "local_tunnel_${id}.service" &>/dev/null
        systemctl restart "local_tunnel_${id}.service" &>/dev/null
    else
        nohup "$runner_script" >/dev/null 2>&1 &
        if command -v crontab &>/dev/null; then
            (crontab -l 2>/dev/null | grep -v "$runner_script"; echo "@reboot $runner_script >/dev/null 2>&1 &") | crontab - 2>/dev/null
        fi
    fi
}

# Ensure every saved tunnel in DB has its runner active
heal_tunnels() {
    [ ! -s "$STATE_FILE" ] && return
    while IFS="|" read -r id proto lport rport; do
        [ -z "$id" ] && continue
        if ! pgrep -f "tunnel_${id}.sh" >/dev/null 2>&1; then
            start_tunnel_processes "$id" "$proto" "$lport" "$rport"
        fi
    done < "$STATE_FILE"
}

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "=========================================================="
    echo "   TWO-WAY PERSISTENT TUNNEL MANAGER (AUTO-RECOVERY)      "
    echo "               Relay VPS: $VPS_HOST                       "
    echo "=========================================================="
    echo -e "${NC}"
}

spawn_tunnel() {
    local local_port="$1"
    local proto="$2"
    local remote_port=""

    read -rp "Enter Public Port on $VPS_HOST (Press Enter for Random Port): " custom_rport
    if [[ "$custom_rport" =~ ^[0-9]+$ ]] && [ "$custom_rport" -ge 1 ] && [ "$custom_rport" -le 60000 ]; then
        remote_port="$custom_rport"
    else
        remote_port=$(get_random_port)
    fi

    local tunnel_id
    tunnel_id=$(date +%s%N | cut -b10-14)

    echo -e "\n${YELLOW}[*] Locking Permanent $proto Port: ${VPS_HOST}:${remote_port} -> 127.0.0.1:${local_port}...${NC}"

    # Save permanently to DB (Never deleted unless manually removed via Option 6)
    echo "$tunnel_id|$proto|$local_port|$remote_port" >> "$STATE_FILE"

    start_tunnel_processes "$tunnel_id" "$proto" "$local_port" "$remote_port"
    sleep 2

    echo -e "${GREEN}${BOLD}[✔] Permanent Tunnel Created & Locked!${NC}"
    echo -e "ID             : ${BOLD}$tunnel_id${NC}"
    echo -e "Protocol       : ${BOLD}$proto${NC}"
    echo -e "Local Target   : ${BOLD}127.0.0.1:$local_port${NC}"
    echo -e "Public Endpoint: ${CYAN}${BOLD}$VPS_HOST:$remote_port${NC} (Will NEVER change after reboot)"
    echo ""
    read -rp "Press Enter to return to menu..."
}

stop_single_tunnel() {
    local id="$1"
    local proto="$2"
    local rport="$3"
    local relay_port=$((rport + 5000))
    local runner_script="$RUNNER_DIR/tunnel_${id}.sh"

    if [ -f "/etc/systemd/system/local_tunnel_${id}.service" ]; then
        systemctl stop "local_tunnel_${id}.service" 2>/dev/null
        systemctl disable "local_tunnel_${id}.service" 2>/dev/null
        rm -f "/etc/systemd/system/local_tunnel_${id}.service"
        systemctl daemon-reload
    fi

    if command -v crontab &>/dev/null; then
        crontab -l 2>/dev/null | grep -v "$runner_script" | crontab - 2>/dev/null
    fi

    local runner_pids
    runner_pids=$(pgrep -f "tunnel_${id}.sh")
    for pid in $runner_pids; do
        pkill -P "$pid" 2>/dev/null
        kill -9 "$pid" 2>/dev/null
    done
    rm -f "$runner_script"

    # Clean remote port & UDP service on VPS 2
    ssh $SSH_OPTS -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" "bash -s" <<EOF 2>/dev/null
fuser -k "${rport}/tcp" >/dev/null 2>&1 || true
fuser -k "${relay_port}/tcp" >/dev/null 2>&1 || true
if [ -f /etc/systemd/system/tunnel_udp_${rport}.service ]; then
    systemctl stop tunnel_udp_${rport}.service 2>/dev/null
    systemctl disable tunnel_udp_${rport}.service 2>/dev/null
    rm -f /etc/systemd/system/tunnel_udp_${rport}.service
    systemctl daemon-reload
fi
EOF
}

list_and_kill_tunnels() {
    while true; do
        heal_tunnels
        print_header
        echo -e "${BOLD}PERMANENT TUNNELS (AUTO-RECONNECTS ON BOTH VPS REBOOTS):${NC}"
        echo "------------------------------------------------------------------------------------------"
        printf "%-8s %-8s %-12s %-28s %-18s\n" "ID" "PROTO" "LOCAL PORT" "PUBLIC ENDPOINT" "LIVE STATUS"
        echo "------------------------------------------------------------------------------------------"

        if [ ! -s "$STATE_FILE" ]; then
            echo -e "${YELLOW}No saved tunnels.${NC}"
            echo "------------------------------------------------------------------------------------------"
            echo ""
            read -rp "Press Enter to return to main menu..."
            break
        fi

        while IFS="|" read -r id proto lport rport; do
            [ -z "$id" ] && continue
            if pgrep -f "0.0.0.0:${rport}:127.0.0.1:${lport}|127.0.0.1:$((rport + 5000)):127.0.0.1:$((rport + 5000))" >/dev/null 2>&1; then
                status="${GREEN}CONNECTED (LIVE)${NC}"
            else
                status="${YELLOW}WAITING FOR VPS...${NC}"
            fi
            printf "%-8s %-8s %-12s %-28s %-b\n" "$id" "$proto" "$lport" "$VPS_HOST:$rport" "$status"
        done < "$STATE_FILE"

        echo "------------------------------------------------------------------------------------------"
        echo ""
        echo "Options: Enter [ID] to permanently delete | [all] to delete all | [0] Back to Main Menu"
        read -rp "Action: " act

        if [ "$act" = "0" ] || [ -z "$act" ]; then
            break
        elif [ "$act" = "all" ]; then
            echo -e "${YELLOW}[*] Permanently deleting all tunnels...${NC}"
            while IFS="|" read -r id proto lport rport; do
                [ -z "$id" ] && continue
                stop_single_tunnel "$id" "$proto" "$rport"
            done < "$STATE_FILE"
            > "$STATE_FILE"
            echo -e "${RED}[✔] All tunnels deleted.${NC}"
            sleep 1
            break
        else
            matched_line=$(grep "^$act|" "$STATE_FILE")
            if [ -n "$matched_line" ]; then
                IFS="|" read -r id proto lport rport <<< "$matched_line"
                echo -e "${YELLOW}[*] Deleting tunnel $id...${NC}"
                stop_single_tunnel "$id" "$proto" "$rport"
                grep -v "^$act|" "$STATE_FILE" > "$STATE_DIR/tmp" && mv "$STATE_DIR/tmp" "$STATE_FILE"
                echo -e "${GREEN}[✔] Deleted tunnel $act.${NC}"
                sleep 1
            else
                echo -e "${RED}[✘] Invalid Tunnel ID.${NC}"
                sleep 1
            fi
        fi
    done
}

prepare_both_vps() {
    echo -e "\n${YELLOW}[*] Step 1: Checking SSH Key for password-less reboot recovery...${NC}"
    if [ ! -f "$HOME/.ssh/id_ed25519" ] && [ ! -f "$HOME/.ssh/id_rsa" ]; then
        ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
    fi

    if ! ssh -q -o BatchMode=yes -o ConnectTimeout=5 -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" exit 2>/dev/null; then
        echo -e "${YELLOW}[*] Copying SSH key to ${VPS_HOST} (Enter VPS 2 password once):${NC}"
        ssh-copy-id -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}"
    fi

    echo -e "${YELLOW}[*] Step 2: Optimizing Remote VPS (${VPS_HOST}) for instant port recovery...${NC}"
    if ssh -q -o BatchMode=yes -o ConnectTimeout=5 -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" exit 2>/dev/null; then
        ssh -p "$SSH_PORT" "${VPS_USER}@${VPS_HOST}" "bash -s" <<'EOF'
if command -v apt-get &>/dev/null; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y socat psmisc lsof >/dev/null 2>&1
fi
sed -i '/^#*GatewayPorts/d' /etc/ssh/sshd_config
sed -i '/^#*ClientAliveInterval/d' /etc/ssh/sshd_config
sed -i '/^#*ClientAliveCountMax/d' /etc/ssh/sshd_config
cat << 'EOT' >> /etc/ssh/sshd_config
GatewayPorts yes
ClientAliveInterval 5
ClientAliveCountMax 2
EOT
systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
EOF
        echo -e "${GREEN}[✔] Both VPS are now linked and configured for instant auto-recovery!${NC}"
    else
        echo -e "${RED}[✘] Could not connect to ${VPS_HOST}. Check IP/SSH Port.${NC}"
    fi
    read -rp "Press Enter to return to menu..."
}

main_menu() {
    check_dependencies
    while true; do
        heal_tunnels
        active_count=$(grep -c "|" "$STATE_FILE" 2>/dev/null || echo 0)

        print_header
        echo -e " Permanent Tunnels Saved: ${GREEN}${BOLD}$active_count${NC}"
        echo " ---------------------------------------------------------"
        echo " [1] Forward SSH (Local Port 22 - TCP)"
        echo " [2] Forward HTTPS / Web (Local Port 443 - TCP)"
        echo " [3] Forward Custom TCP Port"
        echo " [4] Forward Custom UDP Port"
        echo " [5] Forward Custom Dual TCP + UDP Port"
        echo " [6] View Live Status / Delete Tunnels"
        echo " [7] One-Time Setup (Link Both VPS & Enable Instant Rebind)"
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
                prepare_both_vps
                ;;
            0)
                echo -e "\n${CYAN}Exiting CLI. All tunnels are locked in systemd and survive reboots of either VPS.${NC}"
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
