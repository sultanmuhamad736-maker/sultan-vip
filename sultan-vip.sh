#!/bin/bash
# ==========================================================
# SULTAN VIP FULL PURPLE MENU INSTALL
# Full installer + full panel + ready SSL/TLS/SNI/WS/XHTTP
# Same menu structure:
# Main 1-20 + 50 + 99 + X
# Setting 1-29 + 50 + 0
# No nano, no GitHub for the panel file. Xray core uses official Xray installer.
# ==========================================================

set -e
export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" != "0" ]; then
  echo "Run as root."
  exit 1
fi

BASE="/etc/sultan"
XDB="$BASE/xray"
DB="$BASE/users.db"
DOMAIN_FILE="$BASE/domain"
PANEL="/usr/local/bin/menu"

mkdir -p "$BASE" "$XDB"

echo "==========================================="
echo "        SULTAN VIP FULL PURPLE MENU INSTALL"
echo "==========================================="
echo "[1/4] Installing required packages..."
apt update -y
apt install -y curl wget nginx haproxy openssh-server python3 python3-websockify certbot python3-certbot-nginx ufw socat lsb-release bc jq uuid-runtime vnstat fail2ban openssl speedtest-cli dnsutils iproute2 tar gzip ca-certificates psmisc

echo "[2/4] Writing menu panel..."

cat > "$PANEL" <<'PANEL'
#!/bin/bash

BASE="/etc/sultan"
DB="$BASE/users.db"
DOMAIN_FILE="$BASE/domain"
XDB="$BASE/xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"

mkdir -p "$BASE" "$XDB"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAG="\e[35m"
CYAN="\e[36m"
WHITE="\e[97m"
DIM="\e[2m"
NC="\e[0m"

refresh_screen(){
    printf '\033c'
    printf '\033[2J\033[3J\033[H'
    clear
}

pause(){
    echo ""
    read -p "Press Enter..." x
}

box(){
    printf "%-16s :      [ %s ]\n" "$1" "$2"
}

svc(){
    systemctl is-active --quiet "$1" 2>/dev/null && echo "ACTIVE" || echo "OFFLINE"
}

badge(){
    local V="$1"
    if [ "$V" = "ACTIVE" ] || [ "$V" = "READY" ] || [ "$V" = "OK" ]; then
        echo -e "${GREEN}${V}${NC}"
    elif [ "$V" = "OFFLINE" ] || [ "$V" = "FAILED" ] || [ "$V" = "MISSING" ]; then
        echo -e "${RED}${V}${NC}"
    else
        echo -e "${YELLOW}${V}${NC}"
    fi
}

svc_badge(){ badge "$(svc "$1")"; }

verify_service(){
    local SERVICE="$1"
    echo ""
    echo "==================================="
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        echo -e "$SERVICE Status : ${GREEN}[ ACTIVE ]${NC}"
    else
        echo -e "$SERVICE Status : ${RED}[ FAILED ]${NC}"
        echo ""
        echo "Last logs:"
        journalctl -u "$SERVICE" --no-pager -n 25 2>/dev/null || true
    fi
    echo "==================================="
}

get_domain(){ cat "$DOMAIN_FILE" 2>/dev/null || echo "Not Set"; }

get_ip(){
    local IP
    IP="$(curl -s --max-time 4 ipv4.icanhazip.com 2>/dev/null | tr -d '\n')"
    [ -n "$IP" ] && echo "$IP" || hostname -I | awk '{print $1}'
}

get_os(){ lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"'; }
get_cpu(){ top -bn1 | awk '/Cpu/ {print $2"%"}' 2>/dev/null || echo N/A; }
get_ram(){ free -m | awk '/Mem:/ {print $3"MB / "$2"MB"}'; }
get_mem_percent(){ free -m 2>/dev/null | awk '/Mem:/ {printf "%.0f%%", $3/$2*100}'; }
get_disk(){ df -h / | awk 'NR==2 {print $3" / "$2}'; }
get_uptime(){ uptime -p 2>/dev/null | sed 's/up //' || echo unknown; }
get_kernel(){ uname -r; }
get_country(){ curl -s --max-time 4 ipinfo.io/country 2>/dev/null || echo "Unknown"; }
get_isp(){ curl -s --max-time 4 ipinfo.io/org 2>/dev/null | cut -d' ' -f2- || echo "Unknown"; }

count_lines(){ [ -f "$1" ] && wc -l < "$1" || echo 0; }
count_ssh(){ count_lines "$DB"; }
count_vmess(){ count_lines "$XDB/vmess-xhttp.db"; }
count_vless(){ count_lines "$XDB/vless-xhttp.db"; }
count_trojan(){ count_lines "$XDB/trojan-xhttp.db"; }

tls_status(){
    local D
    D="$(get_domain)"
    if [ -d "/etc/letsencrypt/live/$D" ] || [ -f "/etc/letsencrypt/live/$D/fullchain.pem" ]; then
        echo ACTIVE
    else
        echo OFFLINE
    fi
}

bbr_status(){
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        echo ACTIVE
    else
        echo OFFLINE
    fi
}

core_status(){
    if systemctl is-active --quiet nginx 2>/dev/null && systemctl is-active --quiet sultan-ws 2>/dev/null; then
        echo READY
    else
        echo "NEEDS CHECK"
    fi
}

purple_line(){ echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

stats_small(){
    echo "-----------------------------------"
    box "Total SSH Users" "$(count_ssh)"
    box "Total VMESS Users" "$(count_vmess)"
    box "Total VLESS Users" "$(count_vless)"
    box "Total TROJAN Users" "$(count_trojan)"
    box "Online Users" "$(who | wc -l)"
    echo "-----------------------------------"
}

main_menu(){
while true; do
refresh_screen
DOMAIN="$(get_domain)"
IP="$(get_ip)"
UPTIME="$(get_uptime)"
LOAD="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
MEM="$(get_mem_percent)"

echo -e "${MAG}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${MAG}║${WHITE}                    SULTAN VIP                    ${MAG}║${NC}"
echo -e "${MAG}║${CYAN}                  CROWN CORE v1.2                 ${MAG}║${NC}"
echo -e "${MAG}║${GREEN}              SSL | WEBSOCKET | UDP CORE          ${MAG}║${NC}"
echo -e "${MAG}╚════════════════════════════════════════════════════╝${NC}"
echo -e " ${WHITE}Domain${NC}       : ${CYAN}${DOMAIN}${NC}"
echo -e " ${WHITE}Server IP${NC}    : ${CYAN}${IP}${NC}"
echo -e " ${WHITE}Uptime${NC}       : ${GREEN}${UPTIME:-unknown}${NC}"
echo -e " ${WHITE}Memory${NC}       : ${GREEN}${MEM:-unknown}${NC}        ${WHITE}Load${NC}: ${GREEN}${LOAD:-0}${NC}"
purple_line
echo -e " ${WHITE}TLS / SSL${NC}     : $(badge "$(tls_status)")"
echo -e " ${WHITE}WebSocket${NC}     : $(svc_badge sultan-ws)"
echo -e " ${WHITE}XHTTP${NC}         : $(svc_badge xray)"
echo -e " ${WHITE}VMESS${NC}         : $(svc_badge xray)"
echo -e " ${WHITE}VLESS${NC}         : $(svc_badge xray)"
echo -e " ${WHITE}TROJAN${NC}        : $(svc_badge xray)"
echo -e " ${WHITE}UDP Custom${NC}    : $(svc_badge udp-custom)"
echo -e " ${WHITE}Nginx${NC}         : $(svc_badge nginx)"
echo -e " ${WHITE}HAProxy${NC}       : $(svc_badge haproxy)"
echo -e " ${WHITE}SSH${NC}           : $(svc_badge ssh)"
echo -e " ${WHITE}Fail2Ban${NC}      : $(svc_badge fail2ban)"
echo -e " ${WHITE}BBR${NC}           : $(badge "$(bbr_status)")"
echo -e " ${WHITE}Core Status${NC}   : $(badge "$(core_status)")"
purple_line
echo -e " ${CYAN}[1]${NC}  SSH MENU              ${CYAN}[11]${NC} REBOOT VPS"
echo -e " ${CYAN}[2]${NC}  VMESS MENU            ${CYAN}[12]${NC} ABOUT SCRIPT"
echo -e " ${CYAN}[3]${NC}  VLESS MENU            ${CYAN}[13]${NC} VPS INFO"
echo -e " ${CYAN}[4]${NC}  TROJAN MENU           ${CYAN}[14]${NC} ONLINE USERS"
echo -e " ${CYAN}[5]${NC}  SSR MENU              ${CYAN}[15]${NC} SPEEDTEST"
echo -e " ${CYAN}[6]${NC}  UDP CUSTOM            ${CYAN}[16]${NC} DOMAIN MENU"
echo -e " ${CYAN}[7]${NC}  BOT TELEGRAM          ${CYAN}[17]${NC} SSL MENU"
echo -e " ${CYAN}[8]${NC}  UPDATE SCRIPT         ${CYAN}[18]${NC} XRAY MENU"
echo -e " ${CYAN}[9]${NC}  BACKUP RESTORE        ${CYAN}[19]${NC} FAIL2BAN MENU"
echo -e " ${CYAN}[10]${NC} SETTING               ${CYAN}[20]${NC} BBR MENU"
echo ""
echo -e " ${CYAN}[21]${NC} MESSENGER             ${CYAN}[50]${NC} TROUBLESHOOTING"
echo -e " ${RED}[99]${NC} REMOVE SCRIPT          ${YELLOW}[X]${NC}  EXIT"
echo ""
read -p "👉 Select: " opt
[ -z "$opt" ] && continue
case "$opt" in
1) ssh_menu ;;
2) vmess_menu ;;
3) vless_menu ;;
4) trojan_menu ;;
5) ssr_menu ;;
6) udp_menu ;;
7) bot_menu ;;
8) update_script_menu ;;
9) backup_menu ;;
10) setting_menu ;;
11) reboot ;;
12) about_menu ;;
13) vps_info ;;
14) online_users_menu ;;
15) speedtest_menu ;;
16) domain_menu ;;
17) ssl_menu ;;
18) xray_menu ;;
19) fail2ban_menu ;;
20) bbr_menu ;;
21) messenger_menu ;;
50) troubleshooting_menu ;;
99) remove_script ;;
x|X) exit ;;
*) main_menu ;;
esac
done
}

reinstall_package_service(){
    local SERVICE="$1"
    local PACKAGE="$2"
    refresh_screen
    echo "==================================="
    echo "        REINSTALL $SERVICE"
    echo "==================================="
    systemctl stop "$SERVICE" 2>/dev/null || true
    systemctl disable "$SERVICE" 2>/dev/null || true
    apt purge -y "$PACKAGE" 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    apt update -y
    apt install -y "$PACKAGE"
    systemctl enable "$SERVICE" 2>/dev/null || true
    systemctl restart "$SERVICE" 2>/dev/null || true
    verify_service "$SERVICE"
}

restart_ssh_safe(){
    refresh_screen
    echo "==================================="
    echo "          RESTART SSH ONLY"
    echo "==================================="
    echo "SSH will NOT be removed or reinstalled."
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    if systemctl is-active --quiet ssh 2>/dev/null; then
        echo -e "SSH Status : ${GREEN}[ ACTIVE ]${NC}"
    elif systemctl is-active --quiet sshd 2>/dev/null; then
        echo -e "SSHD Status: ${GREEN}[ ACTIVE ]${NC}"
    else
        echo -e "SSH Status : ${RED}[ FAILED ]${NC}"
    fi
}

reinstall_websocket(){
    refresh_screen
    echo "==================================="
    echo "        REINSTALL WEBSOCKET"
    echo "==================================="
    systemctl stop sultan-ws 2>/dev/null || true
    systemctl disable sultan-ws 2>/dev/null || true
    rm -f /etc/systemd/system/sultan-ws.service

    apt update -y
    apt install -y python3-websockify openssh-server

    cat >/etc/systemd/system/sultan-ws.service <<EOL
[Unit]
Description=SULTAN SSH WebSocket
After=network.target

[Service]
ExecStart=/usr/bin/websockify 127.0.0.1:8080 127.0.0.1:22
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable sultan-ws
    systemctl restart sultan-ws
    verify_service sultan-ws
}

reinstall_udp(){
    refresh_screen
    echo "==================================="
    echo "        REINSTALL UDP CUSTOM"
    echo "==================================="
    systemctl stop udp-custom 2>/dev/null || true
    systemctl disable udp-custom 2>/dev/null || true
    rm -f /etc/systemd/system/udp-custom.service

    apt update -y
    apt install -y socat

    cat >/etc/systemd/system/udp-custom.service <<EOL
[Unit]
Description=UDP Custom 7300
After=network.target

[Service]
ExecStart=/usr/bin/socat UDP-LISTEN:7300,fork UDP:127.0.0.1:7300
Restart=always

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable udp-custom
    systemctl restart udp-custom
    ufw allow 7300/udp 2>/dev/null || true
    verify_service udp-custom
}

reinstall_fail2ban(){ reinstall_package_service fail2ban fail2ban; }

reinstall_speedtest(){
    refresh_screen
    echo "==================================="
    echo "        REINSTALL SPEEDTEST"
    echo "==================================="
    apt purge -y speedtest-cli 2>/dev/null || true
    apt update -y
    apt install -y speedtest-cli
    echo -e "Speedtest CLI : ${GREEN}[ INSTALLED ]${NC}"
}

fix_xray_service_root(){
    systemctl stop xray 2>/dev/null || true
    if [ -f /etc/systemd/system/xray.service ]; then
        sed -i 's/^User=.*/User=root/' /etc/systemd/system/xray.service
        sed -i 's/^Group=.*/Group=root/' /etc/systemd/system/xray.service
        grep -q '^User=' /etc/systemd/system/xray.service || sed -i '/^\[Service\]/a User=root' /etc/systemd/system/xray.service
        grep -q '^Group=' /etc/systemd/system/xray.service || sed -i '/^\[Service\]/a Group=root' /etc/systemd/system/xray.service
    fi
    systemctl daemon-reload
}


# ===== REAL SSH LIMITS + TRAFFIC CORE =====
SSH_TRAFFIC_DIR="/var/lib/sultan-ssh-traffic"
SSH_PID_DIR="$SSH_TRAFFIC_DIR/pids"
SSH_TOTAL_DIR="$SSH_TRAFFIC_DIR/total"
SSH_DAILY_DIR="$SSH_TRAFFIC_DIR/daily"
SSH_IP_DIR="$SSH_TRAFFIC_DIR/ips"
SSH_LIMIT_DIR="/etc/ssh/limits"
SSH_MAXLOGIN_DIR="/etc/ssh/maxlogins"
SSH_ENFORCER="/usr/local/bin/sultan-ssh-enforcer"
SSH_ENFORCER_SERVICE="/etc/systemd/system/sultan-ssh-enforcer.service"

ssh_real_dirs(){
    mkdir -p "$SSH_TRAFFIC_DIR" "$SSH_PID_DIR" "$SSH_TOTAL_DIR" "$SSH_DAILY_DIR" "$SSH_IP_DIR" "$SSH_LIMIT_DIR" "$SSH_MAXLOGIN_DIR"
}

safe_name(){
    printf "%s" "$1" | sed 's/[^A-Za-z0-9_.-]/_/g'
}

gb_to_bytes(){
    local V="$1"
    V="$(printf "%s" "$V" | tr 'A-Z' 'a-z' | tr -d ' ')"
    V="${V%gb}"
    V="${V%g}"
    case "$V" in
        ""|0|infinite|unlimited|ultimate|ultimatid|ultimated) echo 0 ;;
        *) awk -v g="$V" 'BEGIN{printf "%.0f", g*1024*1024*1024}' ;;
    esac
}

bytes_to_gb(){
    awk -v b="${1:-0}" 'BEGIN{printf "%.2f GB", b/1024/1024/1024}'
}

normalize_gb_limit(){
    local V="$1"
    V="$(printf "%s" "$V" | tr 'A-Z' 'a-z' | tr -d ' ')"
    V="${V%gb}"
    V="${V%g}"
    case "$V" in
        ""|0|infinite|unlimited|ultimate|ultimatid|ultimated) echo "Infinite" ;;
        *) awk -v g="$V" 'BEGIN{if(g>0){printf "%gGB", g}else{print "Infinite"}}' ;;
    esac
}

normalize_login_limit(){
    local V="$1"
    V="$(printf "%s" "$V" | tr -d ' ')"
    case "$V" in
        ""|0|Infinite|infinite|unlimited|Unlimited) echo "Infinite" ;;
        *) echo "$V" ;;
    esac
}

ssh_counter_file(){
    local DIR="$1"
    local USER="$2"
    echo "$DIR/$(safe_name "$USER")"
}

read_counter(){
    local F="$1"
    [ -f "$F" ] && awk '{print $1+0}' "$F" 2>/dev/null || echo 0
}

write_counter(){
    echo "${2:-0}" > "$1"
}

ssh_valid_user(){
    local U="$1" UIDN
    [ -n "$U" ] || return 1
    [ "$U" != "root" ] || return 1
    [ "$U" != "nobody" ] || return 1
    id "$U" >/dev/null 2>&1 || return 1
    UIDN="$(id -u "$U" 2>/dev/null || echo 0)"
    [ "$UIDN" -ge 1000 ] || return 1
}

ssh_all_users(){
    {
        [ -f "$DB" ] && awk -F'|' 'NF && $1 != "" {print $1}' "$DB"
        awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd 2>/dev/null
    } | sort -u
}

ssh_pid_user(){
    local PID="$1" CMD U
    CMD="$(ps -o args= -p "$PID" 2>/dev/null)"
    U="$(printf "%s" "$CMD" | sed -nE 's/.*sshd: ([^ @\[]+).*/\1/p' | head -1)"
    case "$U" in ""|root|sshd:*) U="$(ps -o user= -p "$PID" 2>/dev/null | awk '{print $1}')" ;; esac
    echo "$U"
}

ssh_peer_ip(){
    local P="$1"
    if printf "%s" "$P" | grep -q '^\['; then
        P="${P#\[}"
        P="${P%\]:*}"
    else
        P="${P%:*}"
    fi
    [ -n "$P" ] && echo "$P" || echo "Unknown"
}

ssh_snapshot(){
    ss -tinpH state established 2>/dev/null | awk '
    /users:\(\("sshd"/ {
        pid=""; peer=$5; sent=0; recv=0
        if (match($0,/pid=[0-9]+/)) pid=substr($0,RSTART+4,RLENGTH-4)
        if (match($0,/bytes_sent:[0-9]+/)) sent=substr($0,RSTART+11,RLENGTH-11)
        if (match($0,/bytes_received:[0-9]+/)) recv=substr($0,RSTART+15,RLENGTH-15)
        if (pid!="" && (sent+recv)>0) {print pid "|" peer "|" sent+recv; pid=""; next}
        lastpid=pid; lastpeer=peer; next
    }
    lastpid!="" {
        sent=0; recv=0
        if (match($0,/bytes_sent:[0-9]+/)) sent=substr($0,RSTART+11,RLENGTH-11)
        if (match($0,/bytes_received:[0-9]+/)) recv=substr($0,RSTART+15,RLENGTH-15)
        print lastpid "|" lastpeer "|" sent+recv
        lastpid=""; lastpeer=""
    }' | while IFS='|' read -r PID PEER BYTES; do
        [ -n "$PID" ] || continue
        U="$(ssh_pid_user "$PID")"
        ssh_valid_user "$U" || continue
        IP="$(ssh_peer_ip "$PEER")"
        echo "$U|$PID|$PEER|$IP|${BYTES:-0}"
    done
}

ssh_track_usage_now(){
    ssh_real_dirs
    local DAY USER PID PEER IP NOW KEY LASTF LAST DELTA TOTALF DAYF OLDF IPF
    DAY="$(date +%F)"
    mkdir -p "$SSH_DAILY_DIR/$DAY"
    ssh_snapshot | while IFS='|' read -r USER PID PEER IP NOW; do
        [ -n "$USER" ] || continue
        KEY="$(safe_name "${USER}_${PID}_${PEER}")"
        LASTF="$SSH_PID_DIR/$KEY.last"
        LAST="$(read_counter "$LASTF")"
        if [ "$NOW" -ge "$LAST" ] 2>/dev/null; then
            DELTA=$((NOW-LAST))
        else
            DELTA="$NOW"
        fi
        write_counter "$LASTF" "$NOW"
        IPF="$SSH_IP_DIR/$(safe_name "$USER").log"
        echo "$(date '+%F %T')|$USER|$IP|$PEER|$PID" >> "$IPF"
        tail -n 3000 "$IPF" > "$IPF.tmp" 2>/dev/null && mv "$IPF.tmp" "$IPF" 2>/dev/null || true
        [ "$DELTA" -gt 0 ] 2>/dev/null || continue
        TOTALF="$(ssh_counter_file "$SSH_TOTAL_DIR" "$USER")"
        DAYF="$(ssh_counter_file "$SSH_DAILY_DIR/$DAY" "$USER")"
        OLDF="$(read_counter "$TOTALF")"; write_counter "$TOTALF" $((OLDF+DELTA))
        OLDF="$(read_counter "$DAYF")"; write_counter "$DAYF" $((OLDF+DELTA))
    done
}

ssh_online_count(){
    ssh_snapshot | awk -F'|' -v u="$1" '$1==u{seen[$2"|"$3]=1} END{for(k in seen)c++; print c+0}'
}

ssh_total_bytes(){
    read_counter "$(ssh_counter_file "$SSH_TOTAL_DIR" "$1")"
}

ssh_today_bytes(){
    local DAY
    DAY="$(date +%F)"
    read_counter "$(ssh_counter_file "$SSH_DAILY_DIR/$DAY" "$1")"
}

ssh_kill_user_sessions(){
    local USER="$1"
    pkill -KILL -u "$USER" 2>/dev/null || true
    ps -eo pid,args | awk -v u="$USER" '$0 ~ "sshd: "u"@" || $0 ~ "sshd: "u" " {print $1}' | xargs -r kill -9 2>/dev/null || true
}

ssh_apply_real_limits(){
    ssh_real_dirs
    mkdir -p /etc/ssh/sshd_config.d /etc/security/limits.d
    cat >/etc/ssh/sshd_config.d/sultan-real-limits.conf <<EOF
UsePAM yes
PasswordAuthentication yes
PermitRootLogin yes
TCPKeepAlive yes
ClientAliveInterval 30
ClientAliveCountMax 6
EOF
    grep -q "pam_limits.so" /etc/pam.d/sshd 2>/dev/null || echo "session required pam_limits.so" >> /etc/pam.d/sshd

    : >/etc/security/limits.d/99-sultan-ssh-maxlogin.conf
    if [ -f "$DB" ]; then
        while IFS='|' read -r USER PASS EXP GB LIMIT; do
            [ -n "$USER" ] || continue
            GB="$(normalize_gb_limit "$GB")"
            LIMIT="$(normalize_login_limit "$LIMIT")"
            echo "$GB" > "$SSH_LIMIT_DIR/$USER"
            echo "$LIMIT" > "$SSH_MAXLOGIN_DIR/$USER"
            if [ "$LIMIT" != "Infinite" ]; then
                echo "$USER hard maxlogins $LIMIT" >> /etc/security/limits.d/99-sultan-ssh-maxlogin.conf
            fi
        done < "$DB"
    fi
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
}

ssh_enforce_now(){
    ssh_track_usage_now
    [ -f "$DB" ] || return
    local NOW USER PASS EXP GB LIMIT QUOTA_BYTES USED_BYTES ONLINE PIDS KEEP PID COUNT
    NOW="$(date +%s)"
    while IFS='|' read -r USER PASS EXP GB LIMIT; do
        [ -n "$USER" ] || continue
        id "$USER" >/dev/null 2>&1 || continue

        if [ "$EXP" != "Infinite" ] && [ -n "$EXP" ]; then
            if [ "$(date -d "$EXP 23:59:59" +%s 2>/dev/null || echo 9999999999)" -lt "$NOW" ]; then
                usermod -L "$USER" 2>/dev/null || true
                ssh_kill_user_sessions "$USER"
                continue
            fi
        fi

        QUOTA_BYTES="$(gb_to_bytes "$GB")"
        USED_BYTES="$(ssh_total_bytes "$USER")"
        if [ "$QUOTA_BYTES" -gt 0 ] 2>/dev/null && [ "$USED_BYTES" -ge "$QUOTA_BYTES" ] 2>/dev/null; then
            usermod -L "$USER" 2>/dev/null || true
            ssh_kill_user_sessions "$USER"
            continue
        fi

        LIMIT="$(normalize_login_limit "$LIMIT")"
        if [ "$LIMIT" != "Infinite" ]; then
            PIDS="$(ps -eo pid,args | awk -v u="$USER" '$0 ~ "sshd: "u"@" || $0 ~ "sshd: "u" " {print $1}' | sort -n)"
            COUNT="$(echo "$PIDS" | awk 'NF{c++} END{print c+0}')"
            if [ "$COUNT" -gt "$LIMIT" ] 2>/dev/null; then
                echo "$PIDS" | awk -v keep="$LIMIT" 'NF{n++; if(n>keep) print $1}' | xargs -r kill -9 2>/dev/null || true
            fi
        fi
    done < "$DB"
}

install_ssh_enforcer(){
    ssh_apply_real_limits
    cat > "$SSH_ENFORCER" <<'ENFORCER'
#!/bin/bash
PANEL="/usr/local/bin/menu"
while true; do
    if [ -x "$PANEL" ]; then
        "$PANEL" --ssh-enforce-once >/dev/null 2>&1 || true
    fi
    sleep 2
done
ENFORCER
    chmod +x "$SSH_ENFORCER"
    cat > "$SSH_ENFORCER_SERVICE" <<EOF
[Unit]
Description=SULTAN Real SSH Limits And Traffic Enforcer
After=network.target ssh.service

[Service]
Type=simple
ExecStart=$SSH_ENFORCER
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable sultan-ssh-enforcer >/dev/null 2>&1 || true
    systemctl restart sultan-ssh-enforcer 2>/dev/null || true
}

ssh_limit_status_text(){
    local USER="$1" GB LIMIT EXP QUOTA USED
    INFO="$(grep "^$USER|" "$DB" 2>/dev/null || true)"
    [ -z "$INFO" ] && return
    IFS='|' read -r _ _ EXP GB LIMIT <<< "$INFO"
    QUOTA="$(gb_to_bytes "$GB")"
    USED="$(ssh_total_bytes "$USER")"
    box "Expire" "$EXP"
    box "Quota" "$(normalize_gb_limit "$GB")"
    box "Used Total" "$(bytes_to_gb "$USED")"
    box "Today" "$(bytes_to_gb "$(ssh_today_bytes "$USER")")"
    box "Online Now" "$(ssh_online_count "$USER")"
    box "Login Limit" "$(normalize_login_limit "$LIMIT")"
    if [ "$QUOTA" -gt 0 ] 2>/dev/null; then
        box "Remaining" "$(bytes_to_gb "$((QUOTA-USED))")"
    fi
}

ssh_online_menu(){
while true; do
refresh_screen
echo "==================================="
echo "          SSH ONLINE USERS"
echo "==================================="
echo "[1] Current online + total since tracker"
echo "[2] Current and saved IPs / hosts"
echo "[3] IPs + usage today and total"
echo "[0] Back"
echo "==================================="
read -p "Select: " O
case "$O" in
1) ssh_user_traffic ;;
2) ssh_users_ips_history ;;
3) ssh_users_ips_usage ;;
0) ssh_menu ;;
*) ssh_online_menu ;;
esac
done
}

ssh_users_ips_history(){
refresh_screen
ssh_track_usage_now
echo "==================================="
echo "      SSH CLIENT IPS / DEVICES"
echo "==================================="
printf "%-14s %-18s %-26s %-19s\n" "USER" "IP" "DEVICE/HOST" "LAST SEEN"
echo "======================================================"
{
ssh_snapshot | awk -F'|' '{print $1 "|" $4 "|" "NOW"}'
for F in "$SSH_IP_DIR"/*.log; do
    [ -f "$F" ] || continue
    tail -n 80 "$F" | awk -F'|' '{print $2 "|" $3 "|" $1}'
done
} | sort -u | while IFS='|' read -r USER IP SEEN; do
    [ -n "$USER" ] || continue
    HOST="$(getent hosts "$IP" 2>/dev/null | awk '{print $2; exit}')"
    [ -n "$HOST" ] || HOST="Unknown"
    printf "%-14s %-18s %-26s %-19s\n" "$USER" "$IP" "$HOST" "$SEEN"
done
echo "======================================================"
echo "Device name depends on reverse DNS. SSH cannot always know the phone model."
pause
}

ssh_users_ips_usage(){
refresh_screen
ssh_track_usage_now
echo "==================================="
echo "      SSH IPS + USAGE"
echo "==================================="
printf "%-14s %-18s %-12s %-14s %-14s\n" "USER" "IP" "ONLINE" "TODAY" "TOTAL"
echo "======================================================"
ssh_snapshot | awk -F'|' '{print $1 "|" $4}' | sort -u | while IFS='|' read -r USER IP; do
    [ -n "$USER" ] || continue
    printf "%-14s %-18s %-12s %-14s %-14s\n" "$USER" "$IP" "$(ssh_online_count "$USER")" "$(bytes_to_gb "$(ssh_today_bytes "$USER")")" "$(bytes_to_gb "$(ssh_total_bytes "$USER")")"
done
echo "======================================================"
pause
}
# ===== END REAL SSH LIMITS + TRAFFIC CORE =====


ssh_db_update_field(){
    local USER="$1" FIELD="$2" VALUE="$3"
    mkdir -p "$BASE"
    touch "$DB"
    awk -F'|' -v u="$USER" -v field="$FIELD" -v val="$VALUE" '
    BEGIN{OFS="|"; found=0}
    $1==u{
        while(NF<5){$(NF+1)="Infinite"}
        $field=val
        found=1
    }
    $1!=""{print}
    END{
        if(!found){
            p="N/A"; e="Infinite"; q="Infinite"; l="Infinite"
            if(field==2)p=val
            if(field==3)e=val
            if(field==4)q=val
            if(field==5)l=val
            print u,p,e,q,l
        }
    }' "$DB" > /tmp/sultan.db && mv /tmp/sultan.db "$DB"
}

ssh_select_user(){
    local TITLE="$1" CHOICE IDX U ONLINE TODAY TOTAL LIMIT
    SELECTED_SSH_USER=""
    ssh_track_usage_now
    mapfile -t SSH_PICK_USERS < <(ssh_all_users)

    refresh_screen
    echo "==================================="
    echo "        $TITLE"
    echo "==================================="

    if [ "${#SSH_PICK_USERS[@]}" -eq 0 ]; then
        echo "No SSH users found"
        pause
        return 1
    fi

    printf "%-5s %-16s %-8s %-14s %-14s %-14s\n" "NO" "SSH USER" "ONLINE" "TODAY" "TOTAL" "LIMIT"
    echo "======================================================"
    IDX=1
    for U in "${SSH_PICK_USERS[@]}"; do
        [ -n "$U" ] || continue
        ONLINE="$(ssh_online_count "$U")"
        TODAY="$(bytes_to_gb "$(ssh_today_bytes "$U")")"
        TOTAL="$(bytes_to_gb "$(ssh_total_bytes "$U")")"
        LIMIT="$(grep "^$U|" "$DB" 2>/dev/null | awk -F'|' '{print $4; exit}')"
        [ -n "$LIMIT" ] || LIMIT="Infinite"
        printf "%-5s %-16s %-8s %-14s %-14s %-14s\n" "[$IDX]" "$U" "$ONLINE" "$TODAY" "$TOTAL" "$LIMIT"
        IDX=$((IDX+1))
    done
    echo "======================================================"
    echo "Type user number or username. Type 0 to go back."
    read -p "Select User: " CHOICE

    [ "$CHOICE" = "0" ] && return 1
    [ -z "$CHOICE" ] && return 1

    case "$CHOICE" in
        ''|*[!0-9]*)
            U="$CHOICE"
            ;;
        *)
            if [ "$CHOICE" -ge 1 ] 2>/dev/null && [ "$CHOICE" -le "${#SSH_PICK_USERS[@]}" ] 2>/dev/null; then
                U="${SSH_PICK_USERS[$((CHOICE-1))]}"
            else
                U="$CHOICE"
            fi
            ;;
    esac

    if ssh_valid_user "$U" || grep -q "^$U|" "$DB" 2>/dev/null; then
        SELECTED_SSH_USER="$U"
        return 0
    fi

    echo "User not found: $U"
    pause
    return 1
}

ssh_current_ips_text(){
    local USER="$1" IPS
    IPS="$(ssh_snapshot | awk -F'|' -v u="$USER" '$1==u{print $4}' | sort -u | paste -sd ',' -)"
    [ -n "$IPS" ] && echo "$IPS" || echo "None"
}

ssh_saved_ips_text(){
    local USER="$1" F
    F="$SSH_IP_DIR/$(safe_name "$USER").log"
    [ -f "$F" ] || { echo "None"; return; }
    awk -F'|' '{print $3}' "$F" | sort -u | tail -n 8 | paste -sd ',' -
}

ssh_show_user_full_info(){
    local USER="$1" INFO U P E Q L
    ssh_track_usage_now
    INFO="$(grep "^$USER|" "$DB" 2>/dev/null | tail -n 1 || true)"
    if [ -n "$INFO" ]; then
        IFS='|' read -r U P E Q L <<< "$INFO"
    else
        U="$USER"
        P="N/A"
        E="$(chage -l "$USER" 2>/dev/null | awk -F': ' '/Account expires/{print $2; exit}')"
        [ -n "$E" ] || E="Unknown"
        Q="$(cat "$SSH_LIMIT_DIR/$USER" 2>/dev/null || echo Infinite)"
        L="$(cat "$SSH_MAXLOGIN_DIR/$USER" 2>/dev/null || echo Infinite)"
    fi

    box "Username" "$U"
    box "Password" "$P"
    box "Expire" "$E"
    box "Quota" "$(normalize_gb_limit "$Q")"
    box "Login Limit" "$(normalize_login_limit "$L")"
    box "Online Now" "$(ssh_online_count "$USER")"
    box "Today Usage" "$(bytes_to_gb "$(ssh_today_bytes "$USER")")"
    box "Total Usage" "$(bytes_to_gb "$(ssh_total_bytes "$USER")")"
    box "Current IPs" "$(ssh_current_ips_text "$USER")"
    box "Saved IPs" "$(ssh_saved_ips_text "$USER")"
}

ssh_change_password_for_user(){
    local USER="$1" PASS
    refresh_screen
    echo "==================================="
    echo "       CHANGE SSH PASSWORD"
    echo "==================================="
    box "Username" "$USER"
    read -s -p "New Password: " PASS
    echo ""
    [ -z "$PASS" ] && { echo "Password required"; pause; return; }
    echo "$USER:$PASS" | chpasswd
    ssh_db_update_field "$USER" 2 "$PASS"
    echo "Password changed"
    pause
}

ssh_change_quota_for_user(){
    local USER="$1" GB GB_TEXT
    refresh_screen
    echo "==================================="
    echo "        CHANGE SSH QUOTA"
    echo "==================================="
    box "Username" "$USER"
    read -p "New GB Limit (0 = Infinite): " GB
    GB_TEXT="$(normalize_gb_limit "$GB")"
    ssh_db_update_field "$USER" 4 "$GB_TEXT"
    ssh_real_dirs
    echo "$GB_TEXT" > "$SSH_LIMIT_DIR/$USER"
    usermod -U "$USER" 2>/dev/null || true
    install_ssh_enforcer
    echo "Quota changed to $GB_TEXT"
    pause
}

ssh_change_login_for_user(){
    local USER="$1" MAXLOGIN LOGIN_TEXT
    refresh_screen
    echo "==================================="
    echo "     CHANGE SSH LOGIN LIMIT"
    echo "==================================="
    box "Username" "$USER"
    read -p "New Login Limit (0 = Infinite): " MAXLOGIN
    case "$MAXLOGIN" in
        ""|*[!0-9]*) echo "Max Login must be number"; pause; return ;;
    esac
    LOGIN_TEXT="$(normalize_login_limit "$MAXLOGIN")"
    ssh_db_update_field "$USER" 5 "$LOGIN_TEXT"
    ssh_real_dirs
    echo "$LOGIN_TEXT" > "$SSH_MAXLOGIN_DIR/$USER"
    install_ssh_enforcer
    echo "Login limit changed to $LOGIN_TEXT"
    pause
}

ssh_extend_for_user(){
    local USER="$1" DAYS EXP
    refresh_screen
    echo "==================================="
    echo "        EXTEND SSH USER"
    echo "==================================="
    box "Username" "$USER"
    read -p "Add days (0 = Infinite): " DAYS
    case "$DAYS" in
        ""|*[!0-9]*) echo "Days must be number"; pause; return ;;
    esac
    if [ "$DAYS" = "0" ]; then
        chage -E -1 "$USER"
        EXP="Infinite"
        echo "Extended Infinite"
    else
        EXP=$(date -d "+$DAYS days" +%Y-%m-%d)
        chage -E "$EXP" "$USER"
        usermod -U "$USER" 2>/dev/null || true
        echo "Extended until $EXP"
    fi
    ssh_db_update_field "$USER" 3 "$EXP"
    install_ssh_enforcer
    pause
}

ssh_delete_for_user(){
    local USER="$1" CONFIRM
    refresh_screen
    echo "==================================="
    echo "        DELETE SSH USER"
    echo "==================================="
    ssh_show_user_full_info "$USER"
    echo "==================================="
    echo "This will kill active sessions and delete Linux user files."
    read -p "Type username to delete: " CONFIRM
    [ "$CONFIRM" = "$USER" ] || { echo "Cancelled"; pause; return; }

    ssh_kill_user_sessions "$USER"
    passwd -l "$USER" 2>/dev/null || true
    usermod -L "$USER" 2>/dev/null || true
    userdel -r "$USER" 2>/dev/null || userdel "$USER" 2>/dev/null || true

    grep -v "^$USER|" "$DB" 2>/dev/null > /tmp/sultan.db || true
    mv /tmp/sultan.db "$DB" 2>/dev/null || true

    rm -f "$SSH_LIMIT_DIR/$USER" "$SSH_MAXLOGIN_DIR/$USER"
    rm -f "$SSH_TOTAL_DIR/$(safe_name "$USER")"
    rm -f "$SSH_DAILY_DIR"/*/"$(safe_name "$USER")" 2>/dev/null || true
    rm -f "$SSH_IP_DIR/$(safe_name "$USER").log" 2>/dev/null || true
    rm -f "$SSH_PID_DIR/$(safe_name "$USER")_"*.last 2>/dev/null || true

    install_ssh_enforcer
    echo "Deleted and killed active sessions: $USER"
    stats_small
    pause
}

ssh_user_info_edit_menu(){
    local USER CH
    ssh_select_user "USER INFORMATION / EDIT" || return
    USER="$SELECTED_SSH_USER"

    while true; do
        refresh_screen
        echo "==================================="
        echo "        USER INFORMATION / EDIT"
        echo "==================================="
        ssh_show_user_full_info "$USER"
        echo "==================================="
        echo "[1] Change Password"
        echo "[2] Change Quota"
        echo "[3] Change Login Limit"
        echo "[4] Extend Days"
        echo "[5] Delete User"
        echo "[0] Back"
        echo "==================================="
        read -p "Select: " CH
        case "$CH" in
            1) ssh_change_password_for_user "$USER" ;;
            2) ssh_change_quota_for_user "$USER" ;;
            3) ssh_change_login_for_user "$USER" ;;
            4) ssh_extend_for_user "$USER" ;;
            5) ssh_delete_for_user "$USER"; return ;;
            0) return ;;
            *) sleep 1 ;;
        esac
    done
}


install_messenger_profile(){
cat >/etc/profile.d/sultan-message.sh <<'EOF'
#!/bin/bash
[ -n "$PS1" ] || return 0 2>/dev/null || exit 0
USER_NAME="$(id -un 2>/dev/null)"
MSG="/etc/sultan/messages/$USER_NAME.txt"
if [ -f "$MSG" ]; then
    echo ""
    echo "==================================="
    echo "          SULTAN MESSAGE"
    echo "==================================="
    tail -n 20 "$MSG" 2>/dev/null
    echo "==================================="
    echo ""
fi
EOF
chmod +x /etc/profile.d/sultan-message.sh
}

messenger_menu(){
local USER MSG DIR TTY
ssh_select_user "MESSENGER" || return
USER="$SELECTED_SSH_USER"
DIR="$BASE/messages"
mkdir -p "$DIR"
install_messenger_profile

refresh_screen
echo "==================================="
echo "             MESSENGER"
echo "==================================="
box "User" "$USER"
echo "Write message. One line only."
read -p "Message: " MSG
[ -z "$MSG" ] && { echo "Empty message cancelled"; pause; return; }

{
echo "[$(date '+%F %T')]"
echo "$MSG"
echo "-----------------------------------"
} >> "$DIR/$USER.txt"
chmod 644 "$DIR/$USER.txt" 2>/dev/null || true

who | awk -v u="$USER" '$1==u{print $2}' | while read -r TTY; do
    [ -n "$TTY" ] || continue
    printf "\n===================================\nSULTAN MESSAGE\n===================================\n%s\n===================================\n" "$MSG" > "/dev/$TTY" 2>/dev/null || true
done

refresh_screen
echo "==================================="
echo "          MESSAGE SAVED"
echo "==================================="
box "User" "$USER"
box "Status" "Saved"
echo ""
echo "If the user has SSH terminal open, message was sent now."
echo "If the user opens shell later, message will appear."
echo "VPN apps may not show shell messages."
pause
}

ssh_menu(){
while true; do
refresh_screen
echo "==================================="
echo "             SSH MENU"
echo "==================================="
echo "[1] Create SSH User"
echo "[2] List SSH Users"
echo "[3] Delete SSH User"
echo "[4] Extend SSH User"
echo "[5] User Information / Edit"
echo "[6] User Traffic"
echo "[7] Online Users"
echo "[8] Change Password"
echo "[9] Change Quota"
echo "[10] Change Login Limit"
echo "[0] Back"
echo "==================================="
read -p "Select: " s
case "$s" in
1) create_ssh_user ;;
2) list_ssh_users ;;
3) delete_ssh_user ;;
4) extend_ssh_user ;;
5) ssh_user_info_edit_menu ;;
6) ssh_user_traffic ;;
7) ssh_online_menu ;;
8) change_ssh_password ;;
9) change_ssh_quota ;;
10) change_ssh_login ;;
0) main_menu ;;
*) ssh_menu ;;
esac
done
}

create_ssh_user(){
refresh_screen
echo "==================================="
echo "        CREATE SSH USER"
echo "==================================="
stats_small
read -p "Username: " USER
read -s -p "Password: " PASS
echo ""
read -p "Days (0 = Infinite): " DAYS
read -p "GB Limit (0 = Infinite): " GB
read -p "Max Login Users (0 = Infinite): " MAXLOGIN

id "$USER" &>/dev/null && { echo "User already exists"; pause; return; }

case "$DAYS" in
    ""|*[!0-9]*) echo "Days must be number"; pause; return ;;
esac
case "$MAXLOGIN" in
    ""|*[!0-9]*) echo "Max Login must be number"; pause; return ;;
esac
GB_TEXT="$(normalize_gb_limit "$GB")"
LOGIN_TEXT="$(normalize_login_limit "$MAXLOGIN")"

useradd -m -s /bin/bash "$USER"
echo "$USER:$PASS" | chpasswd
usermod -U "$USER" 2>/dev/null || true

if [ "$DAYS" = "0" ]; then
    chage -E -1 "$USER"
    EXP="Infinite"
else
    EXP=$(date -d "+$DAYS days" +%Y-%m-%d)
    chage -E "$EXP" "$USER"
fi

grep -v "^$USER|" "$DB" 2>/dev/null > /tmp/sultan.db || true
mv /tmp/sultan.db "$DB" 2>/dev/null || true
echo "$USER|$PASS|$EXP|$GB_TEXT|$LOGIN_TEXT" >> "$DB"

ssh_real_dirs
echo "$GB_TEXT" > "$SSH_LIMIT_DIR/$USER"
echo "$LOGIN_TEXT" > "$SSH_MAXLOGIN_DIR/$USER"
install_ssh_enforcer

refresh_screen
echo "==================================="
echo "        SSH USER CREATED"
echo "==================================="
box "Username" "$USER"
box "Password" "$PASS"
box "Expire" "$EXP"
box "Quota" "$GB_TEXT"
box "Login Limit" "$LOGIN_TEXT"
box "Server IP" "$(get_ip)"
box "Domain" "$(get_domain)"
box "SSH Port" "22"
box "WS/TLS Port" "443"
box "SSH WS Path" "/"
stats_small
echo "==================================="
echo "User was created and saved in database."
echo "Press Enter only after you copy the information."
pause
}

list_ssh_users(){
refresh_screen
echo "==================================="
echo "          SSH USERS LIST"
echo "==================================="
cat "$DB" 2>/dev/null || echo "No users found"
echo "==================================="
pause
}

delete_ssh_user(){
ssh_select_user "DELETE SSH USER" || return
ssh_delete_for_user "$SELECTED_SSH_USER"
}

extend_ssh_user(){
ssh_select_user "EXTEND SSH USER" || return
ssh_extend_for_user "$SELECTED_SSH_USER"
}

ssh_user_info(){
ssh_user_info_edit_menu
}

ssh_user_traffic(){
local CH USER
refresh_screen
echo "==================================="
echo "        SSH USER BANDWIDTH"
echo "==================================="
echo "[1] All users"
echo "[2] Select one user"
echo "[0] Back"
echo "==================================="
read -p "Select: " CH

case "$CH" in
2)
    ssh_select_user "SELECT USER TRAFFIC" || return
    USER="$SELECTED_SSH_USER"
    refresh_screen
    ssh_track_usage_now
    echo "==================================="
    echo "        SSH USER REAL TRAFFIC"
    echo "==================================="
    ssh_show_user_full_info "$USER"
    echo "==================================="
    pause
    return
    ;;
0) return ;;
esac

refresh_screen
ssh_track_usage_now
echo "======================================================"
echo "              SSH USERS LIVE MONITOR"
echo "======================================================"
printf "%-14s %-8s %-14s %-14s %-14s\n" "SSH USER" "ONLINE" "TODAY" "TOTAL" "LIMIT"
echo "======================================================"
if [ -f "$DB" ]; then
    cut -d'|' -f1 "$DB" | while read -r u; do
        [ -n "$u" ] || continue
        online="$(ssh_online_count "$u")"
        today="$(bytes_to_gb "$(ssh_today_bytes "$u")")"
        total="$(bytes_to_gb "$(ssh_total_bytes "$u")")"
        limit="$(grep "^$u|" "$DB" 2>/dev/null | awk -F'|' '{print $4; exit}')"
        [ -n "$limit" ] || limit="Infinite"
        printf "%-14s " "$u"
        if [ "$online" -gt 0 ]; then
            printf "${GREEN}${BOLD}● %-5s${NC} " "$online"
        else
            printf "${RED}● %-5s${NC} " "$online"
        fi
        printf "${YELLOW}%-14s${NC} ${YELLOW}%-14s${NC} %-14s\n" "$today" "$total" "$limit"
    done
else
    echo "No users found"
fi
echo "======================================================"
echo "TODAY = real SSH traffic today"
echo "TOTAL = real SSH traffic since tracker install"
echo "======================================================"
pause
}

change_ssh_password(){
ssh_select_user "CHANGE SSH PASSWORD" || return
ssh_change_password_for_user "$SELECTED_SSH_USER"
}

change_ssh_quota(){
ssh_select_user "CHANGE SSH QUOTA" || return
ssh_change_quota_for_user "$SELECTED_SSH_USER"
}

change_ssh_login(){
ssh_select_user "CHANGE SSH LOGIN LIMIT" || return
ssh_change_login_for_user "$SELECTED_SSH_USER"
}

install_xray(){
refresh_screen
echo "==================================="
echo "        INSTALL / REINSTALL XRAY"
echo "==================================="
echo "This option installs Xray from official XTLS installer."
read -p "Continue? [y/N]: " A
[[ "$A" =~ ^[Yy]$ ]] || return
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fix_xray_service_root
mkdir -p "$XDB"
systemctl enable xray
systemctl restart xray
systemctl status xray --no-pager -n 20 || true
verify_service xray
pause
}

create_xray_config(){
refresh_screen
echo "==================================="
echo "        CREATE XRAY XHTTP CONFIG"
echo "==================================="
DOMAIN=$(get_domain)
[ "$DOMAIN" = "Not Set" ] && read -p "Domain: " DOMAIN && echo "$DOMAIN" > "$DOMAIN_FILE"

mkdir -p /usr/local/etc/xray
cat >/usr/local/etc/xray/config.json <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"tag":"vless-xhttp","listen":"127.0.0.1","port":10000,"protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"xhttp","security":"none","xhttpSettings":{"path":"/vless-xhttp"}}},{"tag":"vmess-xhttp","listen":"127.0.0.1","port":10085,"protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"xhttp","security":"none","xhttpSettings":{"path":"/vmess-xhttp"}}},{"tag":"trojan-xhttp","listen":"127.0.0.1","port":10086,"protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"xhttp","security":"none","xhttpSettings":{"path":"/trojan-xhttp"}}}],"outbounds":[{"protocol":"freedom"}]}
EOF

fix_xray_service_root
systemctl enable xray 2>/dev/null || true
systemctl restart xray 2>/dev/null || true
systemctl status xray --no-pager -n 20 || true
verify_service xray
pause
}

xray_menu(){
while true; do
refresh_screen
echo "==================================="
echo "             XRAY MENU"
echo "==================================="
echo "[1] Install/Reinstall Xray"
echo "[2] Create Base Config"
echo "[3] Restart Xray"
echo "[4] Xray Status"
echo "[5] Show Payload / SNI"
echo "[0] Back"
echo "==================================="
read -p "Select: " x
case "$x" in
1) install_xray ;;
2) create_xray_config ;;
3) refresh_screen; fix_xray_service_root; systemctl restart xray 2>/dev/null || true; systemctl status xray --no-pager -n 20 || true; verify_service xray; pause ;;
4) refresh_screen; systemctl status xray --no-pager || true; pause ;;
5) show_payloads ;;
0) main_menu ;;
*) xray_menu ;;
esac
done
}

create_xray_user_screen(){
    local TITLE="$1"
    refresh_screen
    echo "==================================="
    echo "        CREATE $TITLE USER"
    echo "==================================="
    stats_small
}

ensure_xray_config(){
    if [ ! -f "$XRAY_CONFIG" ]; then
        echo "Xray config not found. Create Base Config first."
        pause
        return 1
    fi
}

vless_menu(){
while true; do
refresh_screen
echo "==================================="
echo "            VLESS MENU"
echo "==================================="
echo "[1] Create VLESS XHTTP"
echo "[2] List VLESS Users"
echo "[3] Delete VLESS User"
echo "[4] User Traffic"
echo "[0] Back"
echo "==================================="
read -p "Select: " v
case "$v" in
1)
ensure_xray_config || continue
create_xray_user_screen "VLESS XHTTP"
read -p "Username: " USER
UUID=$(uuidgen)
DOMAIN=$(get_domain)
mkdir -p "$XDB"
echo "$USER|$UUID|vless|xhttp|$DOMAIN|/vless-xhttp" >> "$XDB/vless-xhttp.db"
jq --arg id "$UUID" --arg email "$USER" '(.inbounds[] | select(.tag=="vless-xhttp") | .settings.clients) += [{"id":$id,"email":$email}]' "$XRAY_CONFIG" > /tmp/xray.json && mv /tmp/xray.json "$XRAY_CONFIG"
systemctl restart xray 2>/dev/null || true
refresh_screen
echo "==================================="
echo "        VLESS XHTTP CREATED"
echo "==================================="
box "Username" "$USER"
box "UUID" "$UUID"
box "Domain" "$DOMAIN"
box "Port" "443"
box "SNI" "$DOMAIN"
box "Type" "XHTTP"
box "Path" "/vless-xhttp"
echo "vless://$UUID@$DOMAIN:443?type=xhttp&security=tls&sni=$DOMAIN&host=$DOMAIN&path=%2Fvless-xhttp#$USER"
stats_small
pause
;;
2) refresh_screen; cat "$XDB/vless-xhttp.db" 2>/dev/null || echo "No VLESS users"; pause ;;
3) delete_xray_user "vless" "vless-xhttp" "id" ;;
4) xray_user_traffic "vless" ;;
0) main_menu ;;
*) vless_menu ;;
esac
done
}

vmess_menu(){
while true; do
refresh_screen
echo "==================================="
echo "            VMESS MENU"
echo "==================================="
echo "[1] Create VMESS XHTTP"
echo "[2] List VMESS Users"
echo "[3] Delete VMESS User"
echo "[4] User Traffic"
echo "[0] Back"
echo "==================================="
read -p "Select: " v
case "$v" in
1)
ensure_xray_config || continue
create_xray_user_screen "VMESS XHTTP"
read -p "Username: " USER
UUID=$(uuidgen)
DOMAIN=$(get_domain)
mkdir -p "$XDB"
echo "$USER|$UUID|vmess|xhttp|$DOMAIN|/vmess-xhttp" >> "$XDB/vmess-xhttp.db"
jq --arg id "$UUID" --arg email "$USER" '(.inbounds[] | select(.tag=="vmess-xhttp") | .settings.clients) += [{"id":$id,"alterId":0,"email":$email}]' "$XRAY_CONFIG" > /tmp/xray.json && mv /tmp/xray.json "$XRAY_CONFIG"
systemctl restart xray 2>/dev/null || true
VMESS_JSON=$(cat <<EOF
{"v":"2","ps":"$USER","add":"$DOMAIN","port":"443","id":"$UUID","aid":"0","scy":"auto","net":"xhttp","type":"none","host":"$DOMAIN","path":"/vmess-xhttp","tls":"tls","sni":"$DOMAIN"}
EOF
)
VMESS_LINK="$(echo -n "$VMESS_JSON" | base64 -w 0 2>/dev/null || echo -n "$VMESS_JSON" | base64 | tr -d '\n')"
refresh_screen
echo "==================================="
echo "        VMESS XHTTP CREATED"
echo "==================================="
box "Username" "$USER"
box "UUID" "$UUID"
box "Domain" "$DOMAIN"
box "Port" "443"
box "SNI" "$DOMAIN"
box "Type" "XHTTP"
box "Path" "/vmess-xhttp"
echo "vmess://$VMESS_LINK"
stats_small
pause
;;
2) refresh_screen; cat "$XDB/vmess-xhttp.db" 2>/dev/null || echo "No VMESS users"; pause ;;
3) delete_xray_user "vmess" "vmess-xhttp" "id" ;;
4) xray_user_traffic "vmess" ;;
0) main_menu ;;
*) vmess_menu ;;
esac
done
}

trojan_menu(){
while true; do
refresh_screen
echo "==================================="
echo "            TROJAN MENU"
echo "==================================="
echo "[1] Create TROJAN XHTTP"
echo "[2] List TROJAN Users"
echo "[3] Delete TROJAN User"
echo "[4] User Traffic"
echo "[0] Back"
echo "==================================="
read -p "Select: " t
case "$t" in
1)
ensure_xray_config || continue
create_xray_user_screen "TROJAN XHTTP"
read -p "Username: " USER
PASS=$(openssl rand -hex 8)
DOMAIN=$(get_domain)
mkdir -p "$XDB"
echo "$USER|$PASS|trojan|xhttp|$DOMAIN|/trojan-xhttp" >> "$XDB/trojan-xhttp.db"
jq --arg password "$PASS" --arg email "$USER" '(.inbounds[] | select(.tag=="trojan-xhttp") | .settings.clients) += [{"password":$password,"email":$email}]' "$XRAY_CONFIG" > /tmp/xray.json && mv /tmp/xray.json "$XRAY_CONFIG"
systemctl restart xray 2>/dev/null || true
refresh_screen
echo "==================================="
echo "        TROJAN XHTTP CREATED"
echo "==================================="
box "Username" "$USER"
box "Password" "$PASS"
box "Domain" "$DOMAIN"
box "Port" "443"
box "SNI" "$DOMAIN"
box "Type" "XHTTP"
box "Path" "/trojan-xhttp"
echo "trojan://$PASS@$DOMAIN:443?type=xhttp&security=tls&sni=$DOMAIN&host=$DOMAIN&path=%2Ftrojan-xhttp#$USER"
stats_small
pause
;;
2) refresh_screen; cat "$XDB/trojan-xhttp.db" 2>/dev/null || echo "No TROJAN users"; pause ;;
3) delete_xray_user "trojan" "trojan-xhttp" "password" ;;
4) xray_user_traffic "trojan" ;;
0) main_menu ;;
*) trojan_menu ;;
esac
done
}

delete_xray_user(){
refresh_screen
PROTO="$1"
TAG="$2"
FIELD="$3"
DBF="$XDB/$PROTO.db"
echo "==================================="
echo "        DELETE ${PROTO^^} USER"
echo "==================================="
read -p "Username: " USER
VALUE=$(grep "^$USER|" "$DBF" 2>/dev/null | cut -d'|' -f2 || true)
if [ -z "$VALUE" ]; then
    echo "User not found"
    pause
    return
fi
if [ -f "$XRAY_CONFIG" ]; then
if [ "$FIELD" = "password" ]; then
    jq --arg value "$VALUE" --arg tag "$TAG" '(.inbounds[] | select(.tag==$tag) | .settings.clients) |= map(select(.password != $value))' "$XRAY_CONFIG" > /tmp/xray.json && mv /tmp/xray.json "$XRAY_CONFIG"
else
    jq --arg value "$VALUE" --arg tag "$TAG" '(.inbounds[] | select(.tag==$tag) | .settings.clients) |= map(select(.id != $value))' "$XRAY_CONFIG" > /tmp/xray.json && mv /tmp/xray.json "$XRAY_CONFIG"
fi
fi
grep -v "^$USER|" "$DBF" > /tmp/xray_user.db || true
mv /tmp/xray_user.db "$DBF"
systemctl restart xray 2>/dev/null || true
echo "Deleted: $USER"
stats_small
pause
}

xray_user_traffic(){
PROTO="$1"
DBF="$XDB/$PROTO.db"
refresh_screen
echo "==================================="
echo "        ${PROTO^^} USER BANDWIDTH"
echo "==================================="
if [ -f "$DBF" ]; then
    cut -d'|' -f1 "$DBF" | while read -r u; do
        printf "%-14s :      [ %s ]\n" "$u" "N/A"
    done
else
    echo "No users found"
fi
echo "==================================="
pause
}

ssr_menu(){
refresh_screen
echo "==================================="
echo "             SSR MENU"
echo "==================================="
echo "SSR core is not installed in this autoscript."
echo "Use VMESS / VLESS / TROJAN / SSH instead."
echo "==================================="
pause
}

fix_403_ws_status(){
bash <<'HAPROXY_443_NGINX_80'
set -e

DOMAIN="s.sultanmuhamad.xyz"
CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
HAPROXY_CERT="/etc/haproxy/certs/$DOMAIN.pem"

echo "=== FORCE HAProxy 443 + Nginx 80 ==="

[ -f "$CERT" ] || { echo "SSL Missing: $CERT"; exit 1; }
[ -f "$KEY" ] || { echo "SSL Key Missing: $KEY"; exit 1; }

BACKUP="/root/BACKUP_HAPROXY443_NGINX80_$(date +%F-%H%M%S)"
mkdir -p "$BACKUP"

cp -a /etc/nginx/conf.d "$BACKUP/nginx_conf.d" 2>/dev/null || true
cp -a /etc/nginx/sites-enabled "$BACKUP/sites-enabled" 2>/dev/null || true
cp -a /etc/haproxy/haproxy.cfg "$BACKUP/haproxy.cfg" 2>/dev/null || true

apt update -y
apt install -y nginx haproxy openssh-server python3-websockify ufw psmisc openssl curl

echo "[1] Stop services..."
systemctl stop nginx haproxy 2>/dev/null || true

echo "[2] Clean old Nginx configs..."
rm -f /etc/nginx/conf.d/*.conf
rm -f /etc/nginx/sites-enabled/*

echo "[3] Start SSH WebSocket backend 8080..."
cat >/etc/systemd/system/sultan-ws.service <<EOF
[Unit]
Description=SULTAN SSH WebSocket Backend
After=network.target ssh.service

[Service]
ExecStart=/usr/bin/websockify 127.0.0.1:8080 127.0.0.1:22
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sultan-ws >/dev/null 2>&1 || true
systemctl restart sultan-ws

echo "[4] Configure Nginx on port 80 only..."
cat >/etc/nginx/conf.d/sultan-nginx-80.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location / {
        return 200 "SULTAN NGINX 80 OK";
        add_header Content-Type text/plain;
    }

    location /block {
        return 403 "SULTAN 403";
        add_header Content-Type text/plain;
    }
}
EOF

echo "[5] Configure HAProxy on port 443 only..."
mkdir -p /etc/haproxy/certs
cat "$CERT" "$KEY" > "$HAPROXY_CERT"
chmod 600 "$HAPROXY_CERT"

cat >/etc/haproxy/haproxy.cfg <<EOF
global
    daemon
    maxconn 10000

defaults
    mode http
    option httplog
    timeout connect 10s
    timeout client  2h
    timeout server  2h
    timeout tunnel  2h

frontend sultan_443
    bind *:443 ssl crt $HAPROXY_CERT alpn http/1.1

    http-request return status 200 content-type text/plain lf-string "SULTAN HAPROXY 443 OK\n" if { path /ok }
    http-request return status 403 content-type text/plain lf-string "SULTAN 403\n" if { path /block }

    default_backend sultan_ssh_ws

backend sultan_ssh_ws
    mode http
    option http-server-close
    server ws 127.0.0.1:8080 check
EOF

echo "[6] Open firewall..."
ufw allow 22/tcp 2>/dev/null || true
ufw allow 80/tcp 2>/dev/null || true
ufw allow 443/tcp 2>/dev/null || true

echo "[7] Test configs..."
nginx -t
haproxy -c -f /etc/haproxy/haproxy.cfg

echo "[8] Restart..."
systemctl enable nginx haproxy >/dev/null 2>&1 || true
systemctl restart nginx
systemctl restart haproxy

sleep 1

echo ""
echo "=== STATUS ==="
echo -n "SSH       : "; systemctl is-active ssh || systemctl is-active sshd || true
echo -n "WebSocket : "; systemctl is-active sultan-ws || true
echo -n "Nginx     : "; systemctl is-active nginx || true
echo -n "HAProxy   : "; systemctl is-active haproxy || true

echo ""
echo "=== WHO OWNS PORTS ==="
ss -tulpn | grep -E ':22|:80|:443|:8080' || true

echo ""
echo "لازم تشوف:"
echo "0.0.0.0:443 = haproxy"
echo "0.0.0.0:80  = nginx"
echo "127.0.0.1:8080 = websockify"
echo ""
echo "Backup: $BACKUP"
HAPROXY_443_NGINX_80
}

setting_menu(){
while true; do
refresh_screen
echo -e "${MAG}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${MAG}║${WHITE}                    SETTING MENU                  ${MAG}║${NC}"
echo -e "${MAG}╚════════════════════════════════════════════════════╝${NC}"
echo -e " ${CYAN}[1]${NC}  Reinstall Nginx              ${CYAN}[16]${NC} Disable Fail2Ban"
echo -e " ${CYAN}[2]${NC}  Disable Nginx                ${CYAN}[17]${NC} Enable BBR"
echo -e " ${CYAN}[3]${NC}  Reinstall HAProxy            ${CYAN}[18]${NC} Disable BBR"
echo -e " ${CYAN}[4]${NC}  Disable HAProxy              ${CYAN}[19]${NC} Restart SSH Only"
echo -e " ${CYAN}[5]${NC}  Reinstall WebSocket          ${CYAN}[20]${NC} Restart Nginx"
echo -e " ${CYAN}[6]${NC}  Disable WebSocket            ${CYAN}[21]${NC} Restart HAProxy"
echo -e " ${CYAN}[7]${NC}  Setup Domain + SSL + XHTTP   ${CYAN}[22]${NC} Restart Xray"
echo -e " ${CYAN}[8]${NC}  Remove SSL/TLS               ${CYAN}[23]${NC} Restart All Services"
echo -e " ${CYAN}[9]${NC}  Reinstall UDP Custom         ${CYAN}[24]${NC} Change Domain"
echo -e " ${CYAN}[10]${NC} Disable UDP Custom           ${CYAN}[25]${NC} Renew SSL"
echo -e " ${CYAN}[11]${NC} Enable UFW                   ${CYAN}[26]${NC} Reinstall Speedtest"
echo -e " ${CYAN}[12]${NC} Disable UFW                  ${CYAN}[27]${NC} Remove Speedtest"
echo -e " ${CYAN}[13]${NC} Open Ports                   ${CYAN}[28]${NC} VPS Information"
echo -e " ${CYAN}[14]${NC} Close Ports                  ${CYAN}[29]${NC} Fix 403-101-200 / HAProxy443 Nginx80"
echo -e " ${CYAN}[15]${NC} Reinstall Fail2Ban"
echo ""
echo -e " ${YELLOW}[50]${NC} TROUBLESHOOTING"
echo -e " ${YELLOW}[0]${NC}  Back"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -p "Select: " s

case "$s" in
1) reinstall_package_service nginx nginx ;;
2) refresh_screen; systemctl stop nginx 2>/dev/null || true; systemctl disable nginx 2>/dev/null || true; echo "Nginx Disabled" ;;
3) reinstall_package_service haproxy haproxy ;;
4) refresh_screen; systemctl stop haproxy 2>/dev/null || true; systemctl disable haproxy 2>/dev/null || true; echo "HAProxy Disabled" ;;
5) reinstall_websocket ;;
6) refresh_screen; systemctl stop sultan-ws 2>/dev/null || true; systemctl disable sultan-ws 2>/dev/null || true; rm -f /etc/systemd/system/sultan-ws.service; systemctl daemon-reload; echo "WebSocket Disabled" ;;
7) setup_domain_ssl_xhttp; install_xray; create_xray_config ;;
8) remove_ssl ;;
9) reinstall_udp ;;
10) refresh_screen; systemctl stop udp-custom 2>/dev/null || true; systemctl disable udp-custom 2>/dev/null || true; rm -f /etc/systemd/system/udp-custom.service; systemctl daemon-reload; echo "UDP Custom Disabled" ;;
11) refresh_screen; apt install -y ufw; ufw --force enable; echo "UFW Enabled" ;;
12) refresh_screen; ufw disable; echo "UFW Disabled" ;;
13) open_ports ;;
14) close_ports ;;
15) reinstall_fail2ban ;;
16) refresh_screen; systemctl stop fail2ban 2>/dev/null || true; systemctl disable fail2ban 2>/dev/null || true; echo "Fail2Ban Disabled" ;;
17) enable_bbr ;;
18) disable_bbr ;;
19) restart_ssh_safe ;;
20) refresh_screen; systemctl restart nginx 2>/dev/null || true; verify_service nginx ;;
21) refresh_screen; systemctl restart haproxy 2>/dev/null || true; verify_service haproxy ;;
22) refresh_screen; fix_xray_service_root; systemctl restart xray 2>/dev/null || true; systemctl status xray --no-pager -n 20 || true; verify_service xray ;;
23) restart_all_services ;;
24) change_domain ;;
25) renew_ssl ;;
26) reinstall_speedtest ;;
27) refresh_screen; apt remove -y speedtest-cli; echo "Speedtest Removed" ;;
28) vps_info ;;
29) fix_403_ws_status ;;
50) troubleshooting_menu ;;
0) main_menu ;;
*) setting_menu ;;
esac
pause
done
}

open_ports(){
refresh_screen
echo "==================================="
echo "            OPEN PORTS"
echo "==================================="
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 7300/udp
ufw --force enable
ufw status
pause
}

close_ports(){
refresh_screen
echo "==================================="
echo "            CLOSE PORTS"
echo "==================================="
ufw delete allow 22/tcp 2>/dev/null || true
ufw delete allow 80/tcp 2>/dev/null || true
ufw delete allow 443/tcp 2>/dev/null || true
ufw delete allow 7300/udp 2>/dev/null || true
ufw status
pause
}

enable_bbr(){
refresh_screen
echo "==================================="
echo "             ENABLE BBR"
echo "==================================="
grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p || true
box "BBR" "$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')"
pause
}

disable_bbr(){
refresh_screen
echo "==================================="
echo "             DISABLE BBR"
echo "==================================="
sed -i '/net.core.default_qdisc/d;/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
sysctl -p || true
echo "BBR removed from sysctl config. Reboot recommended."
pause
}


install_xray_core_auto(){
    if command -v xray >/dev/null 2>&1; then
        return
    fi
    echo "Installing Xray core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install || true
}

create_self_signed_cert(){
    local D="$1"
    mkdir -p "/etc/sultan/selfsigned/$D"
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout "/etc/sultan/selfsigned/$D/privkey.pem" \
        -out "/etc/sultan/selfsigned/$D/fullchain.pem" \
        -subj "/CN=$D" >/dev/null 2>&1 || true
}

cert_file_for_domain(){
    local D="$1"
    if [ -f "/etc/letsencrypt/live/$D/fullchain.pem" ]; then
        echo "/etc/letsencrypt/live/$D/fullchain.pem"
    else
        echo "/etc/sultan/selfsigned/$D/fullchain.pem"
    fi
}

key_file_for_domain(){
    local D="$1"
    if [ -f "/etc/letsencrypt/live/$D/privkey.pem" ]; then
        echo "/etc/letsencrypt/live/$D/privkey.pem"
    else
        echo "/etc/sultan/selfsigned/$D/privkey.pem"
    fi
}

install_sultan_ws_core(){
cat >/usr/local/bin/sultan-ssh-ws <<'PYWS'
#!/usr/bin/env python3
import asyncio, base64, hashlib

async def forward(r, w):
    try:
        while True:
            data = await r.read(8192)
            if not data:
                break
            w.write(data)
            await w.drain()
    except Exception:
        pass
    try:
        w.close()
    except Exception:
        pass

async def handle(cr, cw):
    try:
        header = await cr.readuntil(b"\r\n\r\n")
        text = header.decode(errors="ignore")
        key = ""
        for line in text.split("\r\n"):
            if line.lower().startswith("sec-websocket-key:"):
                key = line.split(":", 1)[1].strip()
        if key:
            accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
            cw.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n").encode())
        else:
            cw.write(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
        await cw.drain()
        sr, sw = await asyncio.open_connection("127.0.0.1", 22)
        await asyncio.gather(forward(cr, sw), forward(sr, cw))
    except Exception:
        try:
            cw.close()
        except Exception:
            pass

async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", 8080)
    async with server:
        await server.serve_forever()

asyncio.run(main())
PYWS

chmod +x /usr/local/bin/sultan-ssh-ws
cat >/etc/systemd/system/sultan-ws.service <<EOF
[Unit]
Description=SULTAN SSH WebSocket Ready
After=network.target

[Service]
ExecStart=/usr/local/bin/sultan-ssh-ws
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sultan-ws
systemctl restart sultan-ws
}

write_ready_xray_config(){
    local D="$1"
    mkdir -p /usr/local/etc/xray
    cat >/usr/local/etc/xray/config.json <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"tag":"vless-xhttp","listen":"127.0.0.1","port":10000,"protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"xhttp","security":"none","xhttpSettings":{"path":"/vless-xhttp"}}},{"tag":"vmess-xhttp","listen":"127.0.0.1","port":10085,"protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"xhttp","security":"none","xhttpSettings":{"path":"/vmess-xhttp"}}},{"tag":"trojan-xhttp","listen":"127.0.0.1","port":10086,"protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"xhttp","security":"none","xhttpSettings":{"path":"/trojan-xhttp"}}}],"outbounds":[{"protocol":"freedom"}]}
EOF
    fix_xray_service_root
    systemctl enable xray 2>/dev/null || true
    systemctl restart xray 2>/dev/null || true
}

write_ready_nginx_haproxy(){
    local D="$1"
    local CERT KEY
    CERT="$(cert_file_for_domain "$D")"
    KEY="$(key_file_for_domain "$D")"

    rm -f /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/default
    cat >/etc/nginx/conf.d/sultan-ready.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $D;

    location / {
        return 200 "SULTAN 200 OK";
        add_header Content-Type text/plain;
    }

    location /block {
        return 403 "SULTAN 403 FORBIDDEN";
        add_header Content-Type text/plain;
    }
}

server {
    listen 127.0.0.1:8443 ssl http2;
    server_name $D;

    ssl_certificate $CERT;
    ssl_certificate_key $KEY;

    location /block {
        return 403 "SULTAN 403 FORBIDDEN";
        add_header Content-Type text/plain;
    }

    location /vless-xhttp {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 0;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    location /vmess-xhttp {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10085;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 0;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    location /trojan-xhttp {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10086;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 0;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    location / {
        if (\$http_upgrade = "") {
            return 200 "SULTAN 200 OK";
        }
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF

    cat >/etc/haproxy/haproxy.cfg <<EOF
global
    daemon
    maxconn 4096

defaults
    mode tcp
    timeout connect 10s
    timeout client 1m
    timeout server 1m

frontend sultan_tls_443
    bind *:443
    default_backend sultan_nginx_tls

backend sultan_nginx_tls
    server nginx_tls 127.0.0.1:8443 check
EOF

    nginx -t
    systemctl enable nginx haproxy
    systemctl restart nginx
    systemctl restart haproxy
}

show_payloads(){
    local D
    D="$(get_domain)"
    [ "$D" = "Not Set" ] && D="$(get_ip)"
    refresh_screen
    echo "==================================="
    echo "        SNI / PAYLOAD / PORTS"
    echo "==================================="
    box "SNI" "$D"
    box "Port TLS" "443"
    box "SSH WS Path" "/"
    box "VLESS XHTTP" "/vless-xhttp"
    box "VMESS XHTTP" "/vmess-xhttp"
    box "TROJAN XHTTP" "/trojan-xhttp"
    echo ""
    echo "SSH WebSocket Payload:"
    echo "GET / HTTP/1.1[crlf]Host: $D[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf]Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==[crlf]Sec-WebSocket-Version: 13[crlf][crlf]"
    echo ""
    echo "VLESS  XHTTP: $D:443  TLS ON  SNI $D  Path /vless-xhttp"
    echo "VMESS  XHTTP: $D:443  TLS ON  SNI $D  Path /vmess-xhttp"
    echo "TROJAN XHTTP: $D:443  TLS ON  SNI $D  Path /trojan-xhttp"
    echo "==================================="
    pause
}

setup_ready_ssl_ws_xhttp(){
    refresh_screen
    echo "==================================="
    echo "   READY SSL/TLS + SNI + WS + XHTTP"
    echo "==================================="
    local D SERVER_IP DOMAIN_IP CERTOK
    D="$(get_domain)"
    if [ "$D" = "Not Set" ] || [ -z "$D" ]; then
        read -p "Enter domain for SSL/SNI: " D
    else
        read -p "Domain [$D]: " ND
        [ -n "$ND" ] && D="$ND"
    fi
    if [ -z "$D" ]; then
        echo "Domain is required."
        pause
        return
    fi
    echo "$D" > "$DOMAIN_FILE"

    SERVER_IP="$(get_ip)"
    DOMAIN_IP="$(getent ahostsv4 "$D" | awk '{print $1; exit}')"
    box "Server IP" "$SERVER_IP"
    box "Domain IP" "${DOMAIN_IP:-EMPTY}"

    apt update -y
    apt install -y curl wget nginx haproxy openssh-server python3 certbot ufw socat jq uuid-runtime psmisc openssl ca-certificates dnsutils

    ufw allow 22/tcp 2>/dev/null || true
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true
    ufw allow 7300/udp 2>/dev/null || true
    ufw --force enable 2>/dev/null || true

    systemctl stop nginx haproxy 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    fuser -k 443/tcp 2>/dev/null || true
    fuser -k 8443/tcp 2>/dev/null || true

    CERTOK=0
    if [ -f "/etc/letsencrypt/live/$D/fullchain.pem" ]; then
        CERTOK=1
    elif [ -n "$DOMAIN_IP" ] && [ "$SERVER_IP" = "$DOMAIN_IP" ]; then
        certbot certonly --standalone -d "$D" --cert-name "$D" --agree-tos -m "admin@$D" --non-interactive --preferred-challenges http && CERTOK=1 || CERTOK=0
    fi

    if [ "$CERTOK" != "1" ]; then
        echo -e "${YELLOW}Valid Let's Encrypt SSL not issued. Creating self-signed fallback so services can start.${NC}"
        create_self_signed_cert "$D"
    fi

    install_sultan_ws_core
    install_xray_core_auto
    write_ready_xray_config "$D"
    reinstall_udp
    write_ready_nginx_haproxy "$D"

    echo ""
    echo "===== STATUS ====="
    echo -n "Port 443: "; ss -tulpn | grep ':443' || true
    echo -n "Nginx: "; systemctl is-active nginx || true
    echo -n "HAProxy: "; systemctl is-active haproxy || true
    echo -n "WebSocket: "; systemctl is-active sultan-ws || true
    echo -n "Xray: "; systemctl is-active xray || true
    echo -n "UDP: "; systemctl is-active udp-custom || true
    echo ""
    show_payloads
}


setup_domain_ssl_xhttp(){
setup_ready_ssl_ws_xhttp
}


remove_ssl(){
refresh_screen
echo "==================================="
echo "           REMOVE SSL/TLS"
echo "==================================="
read -p "Domain: " DOMAIN
certbot delete --cert-name "$DOMAIN" || true
pause
}

renew_ssl(){
refresh_screen
echo "==================================="
echo "             RENEW SSL"
echo "==================================="
certbot renew || true
pause
}

change_domain(){
refresh_screen
echo "==================================="
echo "           CHANGE DOMAIN"
echo "==================================="
read -p "New domain: " DOMAIN
echo "$DOMAIN" > "$DOMAIN_FILE"
box "Domain" "$DOMAIN"
pause
}

restart_all_services(){
refresh_screen
echo "==================================="
echo "        RESTART ALL SERVICES"
echo "==================================="
fix_xray_service_root
systemctl restart ssh nginx haproxy sultan-ws udp-custom xray fail2ban 2>/dev/null || true
verify_service ssh
verify_service nginx
verify_service haproxy
verify_service sultan-ws
verify_service udp-custom
verify_service xray
verify_service fail2ban
pause
}

udp_menu(){
while true; do
refresh_screen
echo "==================================="
echo "           UDP CUSTOM"
echo "==================================="
echo "[1] Reinstall UDP 7300"
echo "[2] Disable UDP 7300"
echo "[0] Back"
echo "==================================="
read -p "Select: " u
case "$u" in
1) reinstall_udp ;;
2) refresh_screen; systemctl stop udp-custom 2>/dev/null || true; systemctl disable udp-custom 2>/dev/null || true; rm -f /etc/systemd/system/udp-custom.service; systemctl daemon-reload; echo "UDP Custom Disabled"; pause ;;
0) main_menu ;;
*) udp_menu ;;
esac
done
}

troubleshooting_menu(){
while true; do
refresh_screen
echo "==================================="
echo "       TROUBLESHOOTING CENTER"
echo "==================================="
echo "[1] Check Nginx"
echo "[2] Check HAProxy"
echo "[3] Check Xray"
echo "[4] Check TLS/SSL"
echo "[5] Check Domain DNS"
echo "[6] Check WebSocket"
echo "[7] Check UDP Custom"
echo "[8] Check Firewall"
echo "[9] Check XHTTP"
echo "[10] Check All Services"
echo "[0] Back"
echo "==================================="
read -p "Select: " t
case "$t" in
1) check_service nginx ;;
2) check_service haproxy ;;
3) check_service xray ;;
4) check_ssl ;;
5) check_dns ;;
6) check_service sultan-ws ;;
7) check_service udp-custom ;;
8) refresh_screen; ufw status; pause ;;
9) check_xhttp ;;
10) check_all ;;
0) setting_menu ;;
*) troubleshooting_menu ;;
esac
done
}

check_service(){
refresh_screen
S="$1"
echo "==================================="
echo "        CHECK $S"
echo "==================================="
box "Service" "$(svc "$S")"
systemctl status "$S" --no-pager 2>/dev/null | head -25 || true
echo "==================================="
pause
}

check_ssl(){
refresh_screen
DOMAIN=$(get_domain)
echo "==================================="
echo "          TLS/SSL CHECK"
echo "==================================="
box "Domain" "$DOMAIN"
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    EXP=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" | cut -d= -f2)
    box "Certificate" "FOUND"
    box "Expire Date" "$EXP"
    box "Status" "ACTIVE"
else
    box "Certificate" "NOT FOUND"
    box "Status" "FAILED"
fi
echo "==================================="
pause
}

check_dns(){
refresh_screen
DOMAIN=$(get_domain)
SERVER_IP=$(get_ip)
DOMAIN_IP=$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}')
echo "==================================="
echo "          DOMAIN DNS CHECK"
echo "==================================="
box "Domain" "$DOMAIN"
box "Server IP" "$SERVER_IP"
box "Domain IP" "${DOMAIN_IP:-EMPTY}"
[ "$SERVER_IP" = "$DOMAIN_IP" ] && box "Result" "OK" || box "Result" "MISMATCH"
echo "==================================="
pause
}

check_xhttp(){
refresh_screen
DOMAIN=$(get_domain)
echo "==================================="
echo "            XHTTP CHECK"
echo "==================================="
box "Xray Service" "$(svc xray)"
box "Domain" "$DOMAIN"
box "TLS Status" "$( [ -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ] && echo ACTIVE || echo FAILED )"
box "Port" "$(ss -tulpn | grep -q ':443' && echo OPEN || echo CLOSED)"
box "XHTTP Path" "/vless-xhttp"
echo "==================================="
pause
}

check_all(){
refresh_screen
for S in nginx haproxy sultan-ws udp-custom xray fail2ban; do
    echo "$S: $(svc "$S")"
done
echo "TLS: $(tls_status)"
echo "BBR: $(bbr_status)"
pause
}

domain_menu(){
while true; do
refresh_screen
echo "==================================="
echo "           DOMAIN MENU"
echo "==================================="
echo "[1] Show Domain"
echo "[2] Change Domain"
echo "[3] Check DNS"
echo "[0] Back"
echo "==================================="
read -p "Select: " d
case "$d" in
1) refresh_screen; box "Domain" "$(get_domain)"; pause ;;
2) change_domain ;;
3) check_dns ;;
0) main_menu ;;
*) domain_menu ;;
esac
done
}

ssl_menu(){
while true; do
refresh_screen
echo "==================================="
echo "             SSL MENU"
echo "==================================="
echo "[1] Install SSL"
echo "[2] Renew SSL"
echo "[3] Remove SSL"
echo "[4] Check SSL"
echo "[0] Back"
echo "==================================="
read -p "Select: " s
case "$s" in
1) setup_domain_ssl_xhttp ;;
2) renew_ssl ;;
3) remove_ssl ;;
4) check_ssl ;;
0) main_menu ;;
*) ssl_menu ;;
esac
done
}

fail2ban_menu(){
while true; do
refresh_screen
echo "==================================="
echo "           FAIL2BAN MENU"
echo "==================================="
echo "[1] Reinstall Fail2Ban"
echo "[2] Disable Fail2Ban"
echo "[3] Status"
echo "[0] Back"
echo "==================================="
read -p "Select: " f
case "$f" in
1) reinstall_fail2ban ;;
2) refresh_screen; systemctl stop fail2ban 2>/dev/null || true; systemctl disable fail2ban 2>/dev/null || true; echo "Fail2Ban Disabled"; pause ;;
3) refresh_screen; systemctl status fail2ban --no-pager || true; pause ;;
0) main_menu ;;
*) fail2ban_menu ;;
esac
done
}

bbr_menu(){
while true; do
refresh_screen
echo "==================================="
echo "             BBR MENU"
echo "==================================="
echo "[1] Enable BBR"
echo "[2] Disable BBR"
echo "[3] Check BBR"
echo "[0] Back"
echo "==================================="
read -p "Select: " b
case "$b" in
1) enable_bbr ;;
2) disable_bbr ;;
3) refresh_screen; sysctl net.ipv4.tcp_congestion_control || true; pause ;;
0) main_menu ;;
*) bbr_menu ;;
esac
done
}

vps_info(){
refresh_screen
echo "==================================="
echo "             VPS INFO"
echo "==================================="
box "OS" "$(get_os)"
box "Kernel" "$(get_kernel)"
box "IP Address" "$(get_ip)"
box "Uptime" "$(get_uptime)"
box "CPU Usage" "$(get_cpu)"
box "RAM Usage" "$(get_ram)"
box "Disk Usage" "$(get_disk)"
box "ISP" "$(get_isp)"
box "Country" "$(get_country)"
echo "==================================="
pause
}

speedtest_menu(){
refresh_screen
echo "==================================="
echo "             SPEEDTEST"
echo "==================================="
speedtest-cli || true
pause
}

online_users_menu(){
refresh_screen
echo "==================================="
echo "           ONLINE USERS"
echo "==================================="
who
echo ""
echo "Active SSH connections:"
ss -tnp | grep ':22' || echo "No SSH connections"
echo "==================================="
pause
}

backup_menu(){
while true; do
refresh_screen
echo "==================================="
echo "        BACKUP & RESTORE"
echo "==================================="
echo "[1] Create Backup"
echo "[2] Restore Backup"
echo "[0] Back"
echo "==================================="
read -p "Select: " b
case "$b" in
1)
refresh_screen
mkdir -p /root/sultan-backup
tar -czf /root/sultan-backup/sultan-backup-$(date +%F-%H%M).tar.gz /etc/sultan /usr/local/etc/xray /usr/local/bin/menu 2>/dev/null || true
echo "Backup saved in /root/sultan-backup/"
pause
;;
2)
refresh_screen
read -p "Backup path: " BP
tar -xzf "$BP" -C /
systemctl restart xray 2>/dev/null || true
echo "Restored"
pause
;;
0) main_menu ;;
*) backup_menu ;;
esac
done
}

bot_menu(){
while true; do
refresh_screen
echo "==================================="
echo "          TELEGRAM BOT"
echo "==================================="
echo "[1] Save Bot Token"
echo "[2] Save Chat ID"
echo "[3] Test Message"
echo "[0] Back"
echo "==================================="
read -p "Select: " b
case "$b" in
1) refresh_screen; read -p "Bot Token: " TOKEN; echo "$TOKEN" > "$BASE/bot_token"; pause ;;
2) refresh_screen; read -p "Chat ID: " CHAT; echo "$CHAT" > "$BASE/chat_id"; pause ;;
3) refresh_screen; TOKEN=$(cat "$BASE/bot_token" 2>/dev/null); CHAT=$(cat "$BASE/chat_id" 2>/dev/null); curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" -d chat_id="$CHAT" -d text="SULTAN Panel Test Message"; echo "Sent"; pause ;;
0) main_menu ;;
*) bot_menu ;;
esac
done
}

update_script_menu(){
refresh_screen
echo "==================================="
echo "          UPDATE SCRIPT"
echo "==================================="
echo "Local full installer build."
echo "No remote update source configured."
echo "==================================="
pause
}

about_menu(){
refresh_screen
echo "==================================="
echo "          ABOUT SULTAN"
echo "==================================="
echo "SULTAN VIP 👑"
echo "Version   : CROWN CORE v1.2 READY"
echo "Design    : Purple VIP"
echo "Ready     : SSL/TLS + SNI + WS + ALL XHTTP"
echo "==================================="
echo ""
echo "[1] Show Payload / SNI Info"
echo "[0] Back"
read -p "Select: " A
case "$A" in
1) show_payloads ;;
*) main_menu ;;
esac
}


remove_script(){
refresh_screen
echo -e "${RED}======================================"
echo "          REMOVE SULTAN SCRIPT"
echo "======================================"
echo " This will remove:"
echo " - SULTAN Panel"
echo " - WebSocket Service"
echo " - UDP Custom Service"
echo " - SULTAN Database"
echo "======================================${NC}"
read -p "Type YES to remove: " CONFIRM
if [ "$CONFIRM" = "YES" ]; then
    systemctl stop sultan-ws udp-custom 2>/dev/null || true
    systemctl disable sultan-ws udp-custom 2>/dev/null || true
    rm -f /etc/systemd/system/sultan-ws.service
    rm -f /etc/systemd/system/udp-custom.service
    rm -rf /etc/sultan
    rm -f /usr/local/bin/menu
    systemctl daemon-reload
    echo "SULTAN removed successfully."
    exit
else
    echo "Cancelled."
    pause
fi
}

case "$1" in
  --ready-install) setup_ready_ssl_ws_xhttp; exit 0 ;;
  --payload) show_payloads; exit 0 ;;
  --ssh-enforce-once) ssh_enforce_now; exit 0 ;;
esac

main_menu
PANEL

echo "[3/4] Setting permissions..."
chmod +x "$PANEL"
"$PANEL" --ssh-enforce-once >/dev/null 2>&1 || true

echo "[4/5] Enabling base services..."
systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
systemctl enable nginx haproxy vnstat fail2ban 2>/dev/null || true
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
systemctl restart vnstat fail2ban 2>/dev/null || true

echo "[5/5] Ready setup: SSL/TLS + SNI + WebSocket + ALL XHTTP + Nginx + HAProxy + 443"
echo "You will be asked for your domain. Make sure DNS A record points to this VPS."
"$PANEL" --ready-install || true

echo ""
echo "==========================================="
echo "Done. Type: menu"
echo "Port 443 is handled by HAProxy -> Nginx TLS."
echo "==========================================="
