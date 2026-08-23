#!/bin/bash

#==============================================================================#
#                                 🚇 Universal Tunnelsmith 🚇                   #
#           PRE-CONFIGURED for YOUR VPS: 103.165.11.161 root1/root             #
#==============================================================================#

# ═════════════════════════════════════════════════════════════════════════════
# YOUR VPS CONFIGURATION - Already set!
REMOTE_HOST="103.165.11.161"
REMOTE_USER="root1"
SSH_PORT="22"
DB_FILE="/tmp/tunnels.db"
# ═════════════════════════════════════════════════════════════════════════════

C_RESET='\u001B[0m' C_RED='\u001B[0;31m' C_GREEN='\u001B[0;32m' 
C_YELLOW='\u001B[0;33m' C_BLUE='\u001B[0;34m' C_PURPLE='\u001B[0;35m' C_CYAN='\u001B[0;36m'
C_WHITE='\u001B[1;37m'

EMOJI_TUNNEL="🚇" EMOJI_SUCCESS="✅" EMOJI_ERROR="❌" EMOJI_LIST="📋" EMOJI_STOP="🛑" EMOJI_GEAR="⚙️"

init_db() {
    mkdir -p /tmp
    touch "$DB_FILE"
}

# Handle password authentication for root/root
ssh_with_pass() {
    expect -c "
        spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $* root1@103.165.11.161 -p 22
        expect "password:"
        send "root
"
        expect eof
    " 2>/dev/null
}

make_tunnel() {
    local LOCAL_PORT=$1
    [[ ! "$LOCAL_PORT" =~ ^[0-9]+$ ]] && { echo -e "${EMOJI_ERROR} ${C_RED}Invalid port${C_RESET}"; return 1; }

    echo -e "${EMOJI_TUNNEL} ${C_BLUE}→ 103.165.11.161:localhost:$LOCAL_PORT...${C_RESET}"
    
    local TMP_LOG=$(mktemp)
    
    # Background SSH tunnel with password handling
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=15 \
        -N -R 0:localhost:$LOCAL_PORT root1@103.165.11.161 -p 22 >"$TMP_LOG" 2>&1 &
    
    local SSH_PID=$!
    
    # Wait for "Allocated port XXXX"
    for i in {1..20}; do
        sleep 0.5
        if grep -q "Allocated port" "$TMP_LOG" 2>/dev/null; then
            break
        fi
        if ! ps -p "$SSH_PID" > /dev/null 2>&1; then
            break
        fi
    done
    
    # Extract port number
    if grep -q "Allocated port" "$TMP_LOG" 2>/dev/null; then
        local REMOTE_PORT=$(grep "Allocated port" "$TMP_LOG" | head -n1 | grep -oE '[0-9]{4,5}')
        echo "$LOCAL_PORT:$REMOTE_PORT:$SSH_PID" >> "$DB_FILE"
        echo -e "${EMOJI_SUCCESS} ${C_GREEN}Tunnel LIVE!${C_RESET}"
        echo -e "  🌐 ${C_CYAN}103.165.11.161:$REMOTE_PORT${C_RESET} → localhost:$LOCAL_PORT"
        echo -e "  🆔 PID: ${C_YELLOW}$SSH_PID${C_RESET}"
        echo -e "  🔗 SSH: ${C_PURPLE}ssh $USER@103.165.11.161 -p $REMOTE_PORT${C_RESET}"
        echo -e "  🌐 Web: ${C_CYAN}http://103.165.11.161:$REMOTE_PORT${C_RESET}"
    else
        echo -e "${EMOJI_ERROR} ${C_RED}❌ Tunnel failed${C_RESET}"
        echo -e "${C_YELLOW}Debug:${C_RESET}"
        tail -10 "$TMP_LOG"
        kill "$SSH_PID" 2>/dev/null
    fi
    rm -f "$TMP_LOG"
}

list_tunnels() {
    init_db
    [[ ! -s "$DB_FILE" ]] && { echo -e "${EMOJI_LIST} ${C_GREEN}No active tunnels${C_RESET}"; return; }
    
    echo -e "${EMOJI_LIST} ${C_BLUE}Live Tunnels (103.165.11.161):${C_RESET}"
    echo "──────────────────────────────────────"
    local count=0
    while IFS=: read -r LPORT RPORT PID; do
        if ps -p "$PID" > /dev/null 2>&1; then
            ((count++))
            echo -e " ${C_CYAN}103.165.11.161:$RPORT${C_RESET} ➤ localhost:${C_PURPLE}$LPORT${C_RESET}"
            echo -e "   PID: ${C_YELLOW}$PID${C_RESET}  🌐 http://103.165.11.161:$RPORT"
        fi
    done < "$DB_FILE"
    [[ $count -eq 0 ]] && echo "${C_YELLOW}No LIVE tunnels (stale data)${C_RESET}"
}

kill_tunnel() {
    [[ -z "$2" ]] && { echo "Usage: $0 kill <port|PID>"; return 1; }
    local target="$2"
    local TMP=$(mktemp)
    local found=0
    while IFS=: read -r LPORT RPORT PID; do
        if [[ "$LPORT" == "$target" || "$PID" == "$target" ]]; then
            if kill "$PID" 2>/dev/null; then
                echo -e "${EMOJI_STOP} ${C_GREEN}Killed port $LPORT (PID $PID)${C_RESET}"
                ((found++))
            fi
        else
            echo "$LPORT:$RPORT:$PID" >> "$TMP"
        fi
    done < "$DB_FILE"
    mv "$TMP" "$DB_FILE"
    [[ $found -eq 0 ]] && echo -e "${EMOJI_ERROR} ${C_RED}Not found: $target${C_RESET}"
}

kill_all() {
    echo -e "${C_RED}🛑 Kill ALL tunnels? (y/N)${C_RESET}"
    read -r confirm
    [[ "$confirm" =~ ^[Yy] ]] && {
        pkill -f "ssh.*103.165.11.161"
        > "$DB_FILE"
        echo -e "${EMOJI_SUCCESS} ${C_GREEN}All tunnels terminated${C_RESET}"
    }
}

setup_vps() {
    echo -e "${EMOJI_GEAR} ${C_YELLOW}Setting up VPS 103.165.11.161...${C_RESET}"
    sshpass -p 'root' ssh -o StrictHostKeyChecking=no root1@103.165.11.161 << 'EOF'
echo "Configuring SSH for tunnels..."
sed -i 's/#GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
sed -i 's/#AllowTcpForwarding no/AllowTcpForwarding yes/' /etc/ssh/sshd_config
systemctl restart ssh
ufw disable 2>/dev/null || iptables -F
echo "✅ VPS configured!"
EOF
}

case "$1" in
    make)
        init_db
        [[ -z "$2" ]] && { echo "Usage: $0 make <port>"; exit 1; }
        make_tunnel "$2"
        ;;
    list)
        list_tunnels
        ;;
    kill)
        init_db
        [[ -z "$2" ]] && { echo "Usage: $0 kill <port|PID>"; exit 1; }
        kill_tunnel "$2"
        ;;
    killall)
        kill_all
        ;;
    setup)
        setup_vps
        ;;
    *)
        cat << EOF
${C_WHITE}🚇 Tunnelsmith - Your VPS Tunnel Manager${C_RESET}
${C_YELLOW}Usage:${C_RESET} $0 {${C_CYAN}make <port>${C_RESET}|${C_CYAN}list${C_RESET}|${C_CYAN}kill <port|PID>${C_RESET}|${C_CYAN}killall${C_RESET}|${C_CYAN}setup${C_RESET}}

${C_PURPLE}🚀 Quick Start:${C_RESET}
  $0 setup           # ONE TIME - configure VPS
  $0 make 8080       # Web server
  $0 make 22         # SSH access
  $0 list            # View tunnels

${C_GREEN}✅ Pre-configured for:${C_RESET}
  Host: 103.165.11.161
  User: root1 / pass: root
EOF
        ;;
esac
