#!/bin/bash
# ==========================================================
# SULTAN VIP FULL PURPLE MENU INSTALL
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
PANEL="/usr/local/bin/hjgjh"

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
echo -e " ${CYAN}[50]${NC} TROUBLESHOOTING       ${RED}[99]${NC} REMOVE SCRIPT"
echo -e " ${YELLOW}[X]${NC}  EXIT"
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
echo "[5] User Information"
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
5) ssh_user_info ;;
6) ssh_user_traffic ;;
7) refresh_screen; who; pause ;;
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

useradd -m -s /bin/bash "$USER"
echo "$USER:$PASS" | chpasswd

if [ "$DAYS" = "0" ]; then
    chage -E -1 "$USER"
    EXP="Infinite"
else
    EXP=$(date -d "+$DAYS days" +%Y-%m-%d)
    chage -E "$EXP" "$USER"
fi

[ "$GB" = "0" ] && GB_TEXT="Infinite" || GB_TEXT="${GB}GB"
[ "$MAXLOGIN" = "0" ] && LOGIN_TEXT="Infinite" || LOGIN_TEXT="$MAXLOGIN"

grep -v "^$USER|" "$DB" 2>/dev/null > /tmp/sultan.db || true
mv /tmp/sultan.db "$DB" 2>/dev/null || true
echo "$USER|$PASS|$EXP|$GB_TEXT|$LOGIN_TEXT" >> "$DB"

refresh_screen
echo "==================================="
echo "        SSH USER CREATED"
echo "==================================="
box "Username" "$USER"
box "Password" "$PASS"
box "Expire" "$EXP"
box "Quota" "$GB_TEXT"
box "Login Limit" "$LOGIN_TEXT"
stats_small
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
refresh_screen
echo "==================================="
echo "        DELETE SSH USER"
echo "==================================="
read -p "Username: " USER
userdel -r "$USER" 2>/dev/null || true
grep -v "^$USER|" "$DB" 2>/dev/null > /tmp/sultan.db || true
mv /tmp/sultan.db "$DB" 2>/dev/null || true
echo "Deleted: $USER"
stats_small
pause
}

extend_ssh_user(){
refresh_screen
echo "==================================="
echo "        EXTEND SSH USER"
echo "==================================="
read -p "Username: " USER
read -p "Add days (0 = Infinite): " DAYS
if [ "$DAYS" = "0" ]; then
    chage -E -1 "$USER"
    echo "Extended Infinite"
else
    EXP=$(date -d "+$DAYS days" +%Y-%m-%d)
    chage -E "$EXP" "$USER"
    echo "Extended until $EXP"
fi
pause
}

ssh_user_info(){
refresh_screen
echo "==================================="
echo "        USER INFORMATION"
echo "==================================="
read -p "Username: " USER
INFO=$(grep "^$USER|" "$DB" 2>/dev/null || true)
if [ -n "$INFO" ]; then
    IFS='|' read -r U P E Q L <<< "$INFO"
    box "Username" "$U"
    box "Password" "$P"
    box "Expire Date" "$E"
    box "Quota" "$Q"
    box "Login Limit" "$L"
else
    echo "User not found"
fi
echo "==================================="
pause
}

ssh_user_traffic(){
refresh_screen
echo "==================================="
echo "        SSH USER BANDWIDTH"
echo "==================================="
if [ -f "$DB" ]; then
    cut -d'|' -f1 "$DB" | while read -r u; do
        printf "%-14s :      [ %s ]\n" "$u" "N/A"
    done
else
    echo "No users found"
fi
echo "==================================="
pause
}

change_ssh_password(){
refresh_screen
echo "==================================="
echo "       CHANGE SSH PASSWORD"
echo "==================================="
read -p "Username: " USER
read -s -p "New Password: " PASS
echo ""
echo "$USER:$PASS" | chpasswd
echo "Password changed"
pause
}

change_ssh_quota(){
refresh_screen
echo "==================================="
echo "        CHANGE SSH QUOTA"
echo "==================================="
read -p "Username: " USER
read -p "New GB Limit (0 = Infinite): " GB
[ "$GB" = "0" ] && GB_TEXT="Infinite" || GB_TEXT="${GB}GB"
awk -F'|' -v u="$USER" -v q="$GB_TEXT" 'BEGIN{OFS="|"} $1==u{$4=q} {print}' "$DB" > /tmp/sultan.db && mv /tmp/sultan.db "$DB"
echo "Quota changed"
pause
}

change_ssh_login(){
refresh_screen
echo "==================================="
echo "     CHANGE SSH LOGIN LIMIT"
echo "==================================="
read -p "Username: " USER
read -p "New Login Limit (0 = Infinite): " MAXLOGIN
[ "$MAXLOGIN" = "0" ] && LOGIN_TEXT="Infinite" || LOGIN_TEXT="$MAXLOGIN"
awk -F'|' -v u="$USER" -v l="$LOGIN_TEXT" 'BEGIN{OFS="|"} $1==u{$5=l} {print}' "$DB" > /tmp/sultan.db && mv /tmp/sultan.db "$DB"
echo "Login limit changed"
pause
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
echo -e " ${CYAN}[14]${NC} Close Ports                  ${CYAN}[29]${NC} Fix 403 / 101 / 200 WebSocket"
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
29) setup_ready_ssl_ws_xhttp ;;
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
tar -czf /root/sultan-backup/sultan-backup-$(date +%F-%H%M).tar.gz /etc/sultan /usr/local/etc/xray /usr/local/bin/hjgjh 2>/dev/null || true
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
    rm -f /usr/local/bin/hjgjh
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
esac

main_menu
PANEL

echo "[3/4] Setting permissions..."
chmod +x "$PANEL"

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
