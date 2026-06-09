#!/bin/bash
# SULTAN VIP AUTOSCRIPT
# Clean screen menus + one-button reinstall/verify services.
# SSH is protected: restart/check only, never purge/reinstall.

set -e

if [ "$(id -u)" != "0" ]; then
  echo "Run as root."
  exit 1
fi

apt update -y
apt install -y curl wget nginx haproxy openssh-server python3-websockify certbot python3-certbot-nginx ufw socat lsb-release bc jq uuid-runtime vnstat fail2ban openssl speedtest-cli dnsutils iproute2

cat >/usr/local/bin/SULTAN <<'PANEL'
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

menu_row(){
    printf "%-22s %s\n" "$1" "$2"
}

svc(){
    systemctl is-active --quiet "$1" && echo "ACTIVE" || echo "OFFLINE"
}

verify_service(){
    local SERVICE="$1"
    echo ""
    echo "==================================="
    if systemctl is-active --quiet "$SERVICE"; then
        echo -e "$SERVICE Status : ${GREEN}[ ACTIVE ]${NC}"
    else
        echo -e "$SERVICE Status : ${RED}[ FAILED ]${NC}"
        echo ""
        echo "Last logs:"
        journalctl -u "$SERVICE" --no-pager -n 25 2>/dev/null || true
    fi
    echo "==================================="
}

get_domain(){
    cat "$DOMAIN_FILE" 2>/dev/null || echo "Not Set"
}

get_ip(){
    curl -s ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}'
}

get_os(){
    lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"'
}

get_cpu(){
    top -bn1 | awk '/Cpu/ {print $2"%"}' 2>/dev/null || echo N/A
}

get_ram(){
    free -m | awk '/Mem:/ {print $3"MB / "$2"MB"}'
}

get_disk(){
    df -h / | awk 'NR==2 {print $3" / "$2}'
}

get_uptime(){
    uptime -p | sed 's/up //'
}

get_kernel(){
    uname -r
}

get_country(){
    curl -s ipinfo.io/country 2>/dev/null || echo "Unknown"
}

get_isp(){
    curl -s ipinfo.io/org 2>/dev/null | cut -d' ' -f2- || echo "Unknown"
}

count_lines(){
    [ -f "$1" ] && wc -l < "$1" || echo 0
}

count_ssh(){ count_lines "$DB"; }
count_vmess(){ count_lines "$XDB/vmess.db"; }
count_vless(){ count_lines "$XDB/vless.db"; }
count_trojan(){ count_lines "$XDB/trojan.db"; }

stats_small(){
    echo "-----------------------------------"
    box "Total SSH Users" "$(count_ssh)"
    box "Total VMESS Users" "$(count_vmess)"
    box "Total VLESS Users" "$(count_vless)"
    box "Total TROJAN Users" "$(count_trojan)"
    box "Online Users" "$(who | wc -l)"
    echo "-----------------------------------"
}

reinstall_package_service(){
    local SERVICE="$1"
    local PACKAGE="$2"

    refresh_screen
    echo "==================================="
    echo "        REINSTALL $SERVICE"
    echo "==================================="
    echo "[1/6] Stop service..."
    systemctl stop "$SERVICE" 2>/dev/null || true

    echo "[2/6] Disable service..."
    systemctl disable "$SERVICE" 2>/dev/null || true

    echo "[3/6] Purge old package/config..."
    apt purge -y "$PACKAGE" 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true

    echo "[4/6] Update packages..."
    apt update -y

    echo "[5/6] Install package..."
    apt install -y "$PACKAGE"

    echo "[6/6] Enable and start..."
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

    if systemctl is-active --quiet ssh; then
        echo -e "SSH Status : ${GREEN}[ ACTIVE ]${NC}"
    elif systemctl is-active --quiet sshd; then
        echo -e "SSHD Status: ${GREEN}[ ACTIVE ]${NC}"
    else
        echo -e "SSH Status : ${RED}[ FAILED ]${NC}"
        journalctl -u ssh --no-pager -n 25 2>/dev/null || journalctl -u sshd --no-pager -n 25 2>/dev/null || true
    fi
}

reinstall_websocket(){
    refresh_screen
    echo "==================================="
    echo "        REINSTALL WEBSOCKET"
    echo "==================================="

    echo "[1/5] Remove old service..."
    systemctl stop sultan-ws 2>/dev/null || true
    systemctl disable sultan-ws 2>/dev/null || true
    rm -f /etc/systemd/system/sultan-ws.service

    echo "[2/5] Install websockify..."
    apt update -y
    apt install -y python3-websockify

    echo "[3/5] Create service..."
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

    echo "[4/5] Reload systemd..."
    systemctl daemon-reload

    echo "[5/5] Start service..."
    systemctl enable sultan-ws
    systemctl restart sultan-ws

    verify_service sultan-ws
}

reinstall_udp(){
    refresh_screen
    echo "==================================="
    echo "        REINSTALL UDP CUSTOM"
    echo "==================================="

    echo "[1/5] Remove old service..."
    systemctl stop udp-custom 2>/dev/null || true
    systemctl disable udp-custom 2>/dev/null || true
    rm -f /etc/systemd/system/udp-custom.service

    echo "[2/5] Install socat..."
    apt update -y
    apt install -y socat

    echo "[3/5] Create service..."
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

    echo "[4/5] Reload systemd..."
    systemctl daemon-reload

    echo "[5/5] Start service..."
    systemctl enable udp-custom
    systemctl restart udp-custom
    ufw allow 7300/udp 2>/dev/null || true

    verify_service udp-custom
}

reinstall_fail2ban(){
    reinstall_package_service fail2ban fail2ban
}

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

main_menu(){
refresh_screen
DOMAIN="$(get_domain)"
D="$DOMAIN"

echo "==========================================="
echo "              SULTAN VIP 👑"
echo "==========================================="
echo ""
box "TLS Status" "$( [ -d "/etc/letsencrypt/live/$D" ] && echo ACTIVE || echo OFFLINE )"
box "SSL Status" "$( [ -d "/etc/letsencrypt/live/$D" ] && echo ACTIVE || echo OFFLINE )"
box "SSH Status" "$(svc ssh)"
box "WebSocket" "$(svc sultan-ws)"
box "XHTTP" "$(svc xray)"
box "VMESS" "$(svc xray)"
box "VLESS" "$(svc xray)"
box "TROJAN" "$(svc xray)"
box "UDP Custom" "$(svc udp-custom)"
box "HAProxy" "$(svc haproxy)"
box "Nginx" "$(svc nginx)"
box "Xray" "$(svc xray)"
box "UFW Firewall" "$(svc ufw)"
box "Fail2Ban" "$(svc fail2ban)"
box "BBR" "$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr && echo ACTIVE || echo OFFLINE)"
echo ""
echo "-------------------------------------------"
echo ""
box "Port SSH" "22"
box "Port TLS" "443"
box "Port HTTP" "80"
box "Port UDPGW" "7300"
echo ""
echo "==========================================="
menu_row "[1] SSH MENU" "[11] REBOOT VPS"
menu_row "[2] VMESS MENU" "[12] ABOUT SCRIPT"
menu_row "[3] VLESS MENU" "[13] VPS INFO"
menu_row "[4] TROJAN MENU" "[14] ONLINE USERS"
menu_row "[5] SSR MENU" "[15] SPEEDTEST"
menu_row "[6] UDP CUSTOM" "[16] DOMAIN MENU"
menu_row "[7] BOT TELEGRAM" "[17] SSL MENU"
menu_row "[8] UPDATE SCRIPT" "[18] XRAY MENU"
menu_row "[9] BACKUP RESTORE" "[19] FAIL2BAN MENU"
menu_row "[10] SETTING" "[20] BBR MENU"
echo ""
echo "-------------------------------------------"
echo ""
box "Total SSH Users" "$(count_ssh)"
box "Total VMESS Users" "$(count_vmess)"
box "Total VLESS Users" "$(count_vless)"
box "Total TROJAN Users" "$(count_trojan)"
echo ""
box "Online Users" "$(who | wc -l)"
box "Bandwidth Today" "$(vnstat --oneline 2>/dev/null | awk -F';' '{print $6}' || echo N/A)"
box "Bandwidth Month" "$(vnstat --oneline 2>/dev/null | awk -F';' '{print $11}' || echo N/A)"
echo ""
echo "-------------------------------------------"
echo ""
echo -e "${YELLOW}[50] TROUBLESHOOTING${NC}"
echo -e "${RED}[99] REMOVE SCRIPT${NC}"
echo "[X] EXIT"
echo ""
echo "==========================================="
read -p "Select option: " opt
[ -z "$opt" ] && main_menu
case "$opt" in
1) ssh_menu ;;
2) vmess_menu ;;
3) vless_menu ;;
4) trojan_menu ;;
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
}
ssh_menu(){
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
7) refresh_screen; who ;;
8) change_ssh_password ;;
9) change_ssh_quota ;;
10) change_ssh_login ;;
0) main_menu ;;
*) ssh_menu ;;
esac
pause
ssh_menu
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

id "$USER" &>/dev/null && { echo "User already exists"; return; }

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

grep -v "^$USER|" "$DB" 2>/dev/null > /tmp/sultan.db
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
}

list_ssh_users(){
refresh_screen
echo "==================================="
echo "          SSH USERS LIST"
echo "==================================="
cat "$DB" 2>/dev/null || echo "No users found"
echo "==================================="
}

delete_ssh_user(){
refresh_screen
echo "==================================="
echo "        DELETE SSH USER"
echo "==================================="
read -p "Username: " USER
userdel -r "$USER" 2>/dev/null || true
grep -v "^$USER|" "$DB" 2>/dev/null > /tmp/sultan.db
mv /tmp/sultan.db "$DB" 2>/dev/null || true
echo "Deleted: $USER"
stats_small
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
}

ssh_user_info(){
refresh_screen
echo "==================================="
echo "        USER INFORMATION"
echo "==================================="
read -p "Username: " USER
INFO=$(grep "^$USER|" "$DB" 2>/dev/null)
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
}

ssh_user_traffic(){
refresh_screen
echo "==================================="
echo "        SSH USER BANDWIDTH"
echo "==================================="
if [ -f "$DB" ]; then
    cut -d'|' -f1 "$DB" | while read u; do
        printf "%-14s :      [ %s ]\n" "$u" "N/A"
    done
else
    echo "No users found"
fi
echo "==================================="
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
}

install_xray(){
refresh_screen
echo "==================================="
echo "        INSTALL / REINSTALL XRAY"
echo "==================================="
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
mkdir -p "$XDB"
systemctl enable xray
systemctl restart xray
verify_service xray
}

create_xray_config(){
refresh_screen
echo "==================================="
echo "        CREATE XRAY BASE CONFIG"
echo "==================================="
DOMAIN=$(get_domain)
[ "$DOMAIN" = "Not Set" ] && read -p "Domain: " DOMAIN && echo "$DOMAIN" > "$DOMAIN_FILE"

mkdir -p /usr/local/etc/xray
cat >/usr/local/etc/xray/config.json <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"tag":"vless-xhttp","listen":"0.0.0.0","port":443,"protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"xhttp","security":"tls","xhttpSettings":{"path":"/xhttp"},"tlsSettings":{"serverName":"$DOMAIN","certificates":[{"certificateFile":"/etc/letsencrypt/live/$DOMAIN/fullchain.pem","keyFile":"/etc/letsencrypt/live/$DOMAIN/privkey.pem"}]}}},{"tag":"vmess-ws","listen":"127.0.0.1","port":10085,"protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"ws","wsSettings":{"path":"/vmess"}}},{"tag":"trojan-ws","listen":"127.0.0.1","port":10086,"protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"ws","wsSettings":{"path":"/trojan"}}}],"outbounds":[{"protocol":"freedom"}]}
EOF

systemctl restart xray 2>/dev/null || true
verify_service xray
}

xray_menu(){
refresh_screen
echo "==================================="
echo "             XRAY MENU"
echo "==================================="
echo "[1] Install/Reinstall Xray"
echo "[2] Create Base Config"
echo "[3] Restart Xray"
echo "[4] Xray Status"
echo "[0] Back"
echo "==================================="
read -p "Select: " x
case "$x" in
1) install_xray ;;
2) create_xray_config ;;
3) refresh_screen; systemctl restart xray; verify_service xray ;;
4) refresh_screen; systemctl status xray --no-pager ;;
0) main_menu ;;
*) xray_menu ;;
esac
pause
xray_menu
}

create_xray_user_screen(){
    local TITLE="$1"
    refresh_screen
    echo "==================================="
    echo "        CREATE $TITLE USER"
    echo "==================================="
    stats_small
}

vless_menu(){
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
create_xray_user_screen "VLESS"
read -p "Username: " USER
UUID=$(uuidgen)
DOMAIN=$(get_domain)
mkdir -p "$XDB"
echo "$USER|$UUID|vless|xhttp|$DOMAIN|/xhttp" >> "$XDB/vless.db"
jq --arg id "$UUID" --arg email "$USER" '(.inbounds[] | select(.tag=="vless-xhttp") | .settings.clients) += [{"id":$id,"email":$email}]' "$XRAY_CONFIG" > /tmp/xray.json && mv /tmp/xray.json "$XRAY_CONFIG"
systemctl restart xray
refresh_screen
echo "==================================="
echo "        VLESS XHTTP CREATED"
echo "==================================="
box "Username" "$USER"
box "UUID" "$UUID"
box "Domain" "$DOMAIN"
box "Port" "443"
box "Path" "/xhttp"
echo "vless://$UUID@$DOMAIN:443?type=xhttp&security=tls&path=%2Fxhttp#$USER"
stats_small
;;
2) refresh_screen; cat "$XDB/vless.db" 2>/dev/null || echo "No VLESS users" ;;
3) delete_xray_user "vless" "vless-xhttp" "id" ;;
4) xray_user_traffic "vless" ;;
0) main_menu ;;
*) vless_menu ;;
esac
pause
vless_menu
}

vmess_menu(){
refresh_screen
echo "==================================="
echo "            VMESS MENU"
echo "==================================="
echo "[1] Create VMESS WS"
echo "[2] List VMESS Users"
echo "[3] Delete VMESS User"
echo "[4] User Traffic"
echo "[0] Back"
echo "==================================="
read -p "Select: " v
case "$v" in
1)
create_xray_user_screen "VMESS"
read -p "Username: " USER
UUID=$(uuidgen)
DOMAIN=$(get_domain)
mkdir -p "$XDB"
echo "$USER|$UUID|vmess|ws|$DOMAIN|/vmess" >> "$XDB/vmess.db"
jq --arg id "$UUID" --arg email "$USER" '(.inbounds[] | select(.tag=="vmess-ws") | .settings.clients) += [{"id":$id,"alterId":0,"email":$email}]' "$XRAY_CONFIG" > /tmp/xray.json && mv /tmp/xray.json "$XRAY_CONFIG"
systemctl restart xray
refresh_screen
echo "==================================="
echo "          VMESS CREATED"
echo "==================================="
box "Username" "$USER"
box "UUID" "$UUID"
box "Domain" "$DOMAIN"
box "Path" "/vmess"
stats_small
;;
2) refresh_screen; cat "$XDB/vmess.db" 2>/dev/null || echo "No VMESS users" ;;
3) delete_xray_user "vmess" "vmess-ws" "id" ;;
4) xray_user_traffic "vmess" ;;
0) main_menu ;;
*) vmess_menu ;;
esac
pause
vmess_menu
}

trojan_menu(){
refresh_screen
echo "==================================="
echo "            TROJAN MENU"
echo "==================================="
echo "[1] Create TROJAN WS"
echo "[2] List TROJAN Users"
echo "[3] Delete TROJAN User"
echo "[4] User Traffic"
echo "[0] Back"
echo "==================================="
read -p "Select: " t
case "$t" in
1)
create_xray_user_screen "TROJAN"
read -p "Username: " USER
PASS=$(openssl rand -hex 8)
DOMAIN=$(get_domain)
mkdir -p "$XDB"
echo "$USER|$PASS|trojan|ws|$DOMAIN|/trojan" >> "$XDB/trojan.db"
jq --arg password "$PASS" --arg email "$USER" '(.inbounds[] | select(.tag=="trojan-ws") | .settings.clients) += [{"password":$password,"email":$email}]' "$XRAY_CONFIG" > /tmp/xray.json && mv /tmp/xray.json "$XRAY_CONFIG"
systemctl restart xray
refresh_screen
echo "==================================="
echo "          TROJAN CREATED"
echo "==================================="
box "Username" "$USER"
box "Password" "$PASS"
box "Domain" "$DOMAIN"
box "Path" "/trojan"
echo "trojan://$PASS@$DOMAIN:443?type=ws&security=tls&path=%2Ftrojan#$USER"
stats_small
;;
2) refresh_screen; cat "$XDB/trojan.db" 2>/dev/null || echo "No TROJAN users" ;;
3) delete_xray_user "trojan" "trojan-ws" "password" ;;
4) xray_user_traffic "trojan" ;;
0) main_menu ;;
*) trojan_menu ;;
esac
pause
trojan_menu
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
VALUE=$(grep "^$USER|" "$DBF" 2>/dev/null | cut -d'|' -f2)

if [ -z "$VALUE" ]; then
    echo "User not found"
    return
fi

if [ "$FIELD" = "password" ]; then
    jq --arg value "$VALUE" --arg tag "$TAG" '(.inbounds[] | select(.tag==$tag) | .settings.clients) |= map(select(.password != $value))' "$XRAY_CONFIG" > /tmp/xray.json && mv /tmp/xray.json "$XRAY_CONFIG"
else
    jq --arg value "$VALUE" --arg tag "$TAG" '(.inbounds[] | select(.tag==$tag) | .settings.clients) |= map(select(.id != $value))' "$XRAY_CONFIG" > /tmp/xray.json && mv /tmp/xray.json "$XRAY_CONFIG"
fi

grep -v "^$USER|" "$DBF" > /tmp/xray_user.db
mv /tmp/xray_user.db "$DBF"
systemctl restart xray
echo "Deleted: $USER"
stats_small
}

xray_user_traffic(){
PROTO="$1"
DBF="$XDB/$PROTO.db"
refresh_screen
echo "==================================="
echo "        ${PROTO^^} USER BANDWIDTH"
echo "==================================="
if [ -f "$DBF" ]; then
    cut -d'|' -f1 "$DBF" | while read u; do
        printf "%-14s :      [ %s ]\n" "$u" "N/A"
    done
else
    echo "No users found"
fi
echo "==================================="
}

setting_menu(){
refresh_screen
echo "==================================="
echo "          SETTING MENU"
echo "==================================="
echo "[1] Reinstall Nginx"
echo "[2] Disable Nginx"
echo ""
echo "[3] Reinstall HAProxy"
echo "[4] Disable HAProxy"
echo ""
echo "[5] Reinstall WebSocket"
echo "[6] Disable WebSocket"
echo ""
echo "[7] Setup Domain + SSL + XHTTP"
echo "[8] Remove SSL/TLS"
echo ""
echo "[9] Reinstall UDP Custom"
echo "[10] Disable UDP Custom"
echo ""
echo "[11] Enable UFW"
echo "[12] Disable UFW"
echo ""
echo "[13] Open Ports"
echo "[14] Close Ports"
echo ""
echo "[15] Reinstall Fail2Ban"
echo "[16] Disable Fail2Ban"
echo ""
echo "[17] Enable BBR"
echo "[18] Disable BBR"
echo ""
echo "[19] Restart SSH Only"
echo "[20] Restart Nginx"
echo "[21] Restart HAProxy"
echo "[22] Restart Xray"
echo ""
echo "[23] Restart All Services"
echo ""
echo "[24] Change Domain"
echo "[25] Renew SSL"
echo ""
echo "[26] Reinstall Speedtest"
echo "[27] Remove Speedtest"
echo ""
echo "[28] VPS Information"
echo ""
echo -e "${YELLOW}[50] TROUBLESHOOTING${NC}"
echo ""
echo "[0] Back"
echo "==================================="
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
20) refresh_screen; systemctl restart nginx; verify_service nginx ;;
21) refresh_screen; systemctl restart haproxy; verify_service haproxy ;;
22) refresh_screen; systemctl restart xray; verify_service xray ;;
23) restart_all_services ;;
24) change_domain ;;
25) renew_ssl ;;
26) reinstall_speedtest ;;
27) refresh_screen; apt remove -y speedtest-cli; echo "Speedtest Removed" ;;
28) vps_info ;;
50) troubleshooting_menu ;;
0) main_menu ;;
*) setting_menu ;;
esac
pause
setting_menu
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
}

enable_bbr(){
refresh_screen
echo "==================================="
echo "             ENABLE BBR"
echo "==================================="
grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
box "BBR" "$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')"
}

disable_bbr(){
refresh_screen
echo "==================================="
echo "             DISABLE BBR"
echo "==================================="
sed -i '/net.core.default_qdisc/d;/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
sysctl -p
echo "BBR removed from sysctl config. Reboot recommended."
}

setup_domain_ssl_xhttp(){
refresh_screen
echo "==================================="
echo "      SETUP DOMAIN SSL XHTTP"
echo "==================================="
read -p "Domain: " DOMAIN
echo "$DOMAIN" > "$DOMAIN_FILE"

SERVER_IP=$(get_ip)
DOMAIN_IP=$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}')

box "Server IP" "$SERVER_IP"
box "Domain IP" "$DOMAIN_IP"

if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
    echo -e "${RED}DNS mismatch. Point domain to this VPS first.${NC}"
    return
fi

apt install -y nginx certbot python3-certbot-nginx
ufw allow 80/tcp 2>/dev/null || true
ufw allow 443/tcp 2>/dev/null || true
systemctl enable nginx
systemctl restart nginx

certbot --nginx -d "$DOMAIN" --agree-tos -m admin@$DOMAIN --non-interactive --redirect

if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo -e "TLS Status : ${GREEN}[ ACTIVE ]${NC}"
else
    echo -e "TLS Status : ${RED}[ FAILED ]${NC}"
fi
}

remove_ssl(){
refresh_screen
echo "==================================="
echo "           REMOVE SSL/TLS"
echo "==================================="
read -p "Domain: " DOMAIN
certbot delete --cert-name "$DOMAIN"
}

renew_ssl(){
refresh_screen
echo "==================================="
echo "             RENEW SSL"
echo "==================================="
certbot renew
}

change_domain(){
refresh_screen
echo "==================================="
echo "           CHANGE DOMAIN"
echo "==================================="
read -p "New domain: " DOMAIN
echo "$DOMAIN" > "$DOMAIN_FILE"
box "Domain" "$DOMAIN"
}

restart_all_services(){
refresh_screen
echo "==================================="
echo "        RESTART ALL SERVICES"
echo "==================================="
systemctl restart ssh nginx haproxy sultan-ws udp-custom xray fail2ban 2>/dev/null || true
verify_service ssh
verify_service nginx
verify_service haproxy
verify_service sultan-ws
verify_service udp-custom
verify_service xray
verify_service fail2ban
}

udp_menu(){
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
2) refresh_screen; systemctl stop udp-custom 2>/dev/null || true; systemctl disable udp-custom 2>/dev/null || true; rm -f /etc/systemd/system/udp-custom.service; systemctl daemon-reload; echo "UDP Custom Disabled" ;;
0) main_menu ;;
*) udp_menu ;;
esac
pause
udp_menu
}

troubleshooting_menu(){
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
8) refresh_screen; ufw status ;;
9) check_xhttp ;;
10) check_all ;;
0) setting_menu ;;
*) troubleshooting_menu ;;
esac
pause
troubleshooting_menu
}

check_service(){
refresh_screen
S="$1"
echo "==================================="
echo "        CHECK $S"
echo "==================================="
box "Service" "$(svc $S)"
systemctl status "$S" --no-pager 2>/dev/null | head -25
echo "==================================="
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
box "Domain IP" "$DOMAIN_IP"
[ "$SERVER_IP" = "$DOMAIN_IP" ] && box "Result" "OK" || box "Result" "MISMATCH"
echo "==================================="
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
box "XHTTP Path" "/xhttp"
echo "==================================="
}

check_all(){
refresh_screen
check_service nginx
check_service haproxy
check_service sultan-ws
check_service udp-custom
check_service xray
check_ssl
check_dns
}

domain_menu(){
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
1) refresh_screen; box "Domain" "$(get_domain)" ;;
2) change_domain ;;
3) check_dns ;;
0) main_menu ;;
*) domain_menu ;;
esac
pause
domain_menu
}

ssl_menu(){
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
pause
ssl_menu
}

fail2ban_menu(){
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
2) refresh_screen; systemctl stop fail2ban 2>/dev/null || true; systemctl disable fail2ban 2>/dev/null || true; echo "Fail2Ban Disabled" ;;
3) refresh_screen; systemctl status fail2ban --no-pager ;;
0) main_menu ;;
*) fail2ban_menu ;;
esac
pause
fail2ban_menu
}

bbr_menu(){
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
3) refresh_screen; sysctl net.ipv4.tcp_congestion_control ;;
0) main_menu ;;
*) bbr_menu ;;
esac
pause
bbr_menu
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
main_menu
}

speedtest_menu(){
refresh_screen
echo "==================================="
echo "             SPEEDTEST"
echo "==================================="
speedtest-cli
pause
main_menu
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
main_menu
}

backup_menu(){
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
tar -czf /root/sultan-backup/sultan-backup-$(date +%F-%H%M).tar.gz /etc/sultan /usr/local/etc/xray /usr/local/bin/SULTAN 2>/dev/null
echo "Backup saved in /root/sultan-backup/"
;;
2)
refresh_screen
read -p "Backup path: " BP
tar -xzf "$BP" -C /
systemctl restart xray 2>/dev/null || true
echo "Restored"
;;
0) main_menu ;;
*) backup_menu ;;
esac
pause
backup_menu
}

bot_menu(){
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
1) refresh_screen; read -p "Bot Token: " TOKEN; echo "$TOKEN" > "$BASE/bot_token" ;;
2) refresh_screen; read -p "Chat ID: " CHAT; echo "$CHAT" > "$BASE/chat_id" ;;
3) refresh_screen; TOKEN=$(cat "$BASE/bot_token" 2>/dev/null); CHAT=$(cat "$BASE/chat_id" 2>/dev/null); curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" -d chat_id="$CHAT" -d text="SULTAN Panel Test Message"; echo "Sent" ;;
0) main_menu ;;
*) bot_menu ;;
esac
pause
bot_menu
}

update_script_menu(){
refresh_screen
echo "==================================="
echo "          UPDATE SCRIPT"
echo "==================================="
echo "No remote update source configured."
echo "==================================="
pause
main_menu
}

about_menu(){
refresh_screen
echo "==================================="
echo "          ABOUT SULTAN"
echo "==================================="
echo "SULTAN VIP 👑"
echo "Developer : SULTAN VIP 👑"
echo "Version   : SULTAN VIP 👑 Final"
echo "==================================="
pause
main_menu
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
    rm -f /usr/local/bin/SULTAN
    systemctl daemon-reload
    echo "SULTAN removed successfully."
    exit
else
    echo "Cancelled."
    pause
    main_menu
fi
}

main_menu
PANEL

chmod +x /usr/local/bin/SULTAN
systemctl enable ssh nginx haproxy vnstat 2>/dev/null || true
systemctl restart ssh nginx haproxy vnstat 2>/dev/null || true

echo "Done. Type: SULTAN"
