#!/bin/bash
# ==========================================================
# SULTAN VIP - STANDALONE SETTINGS & SERVICES FIXER
# ==========================================================

if [ "$(id -u)" != "0" ]; then
  echo "Run as root."
  exit 1
fi

DOMAIN_FILE="/etc/sultan/domain"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAG="\e[35m"
CYAN="\e[36m"
WHITE="\e[97m"
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

vps_info(){
    refresh_screen
    box "OS" "$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
    box "Kernel" "$(uname -r)"
    box "IP Address" "$(get_ip)"
    box "Uptime" "$(uptime -p 2>/dev/null | sed 's/up //')"
    box "RAM Usage" "$(free -m | awk '/Mem:/ {print $3"MB / "$2"MB"}')"
    box "Disk Usage" "$(df -h / | awk 'NR==2 {print $3" / "$2}')"
    pause
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

fix_403_ws_status(){
    refresh_screen
    D="$(cat /etc/sultan/domain 2>/dev/null || echo sl.sultanmuhamad.xyz)"

    echo "==================================="
    echo "      FIX 403 / 101 / 200 WS"
    echo "==================================="
    echo "Domain: $D"
    echo ""

    apt update -y
    apt install -y nginx python3 openssh-server psmisc

    systemctl stop nginx haproxy sultan-ws 2>/dev/null || true
    systemctl disable haproxy 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    fuser -k 443/tcp 2>/dev/null || true
    fuser -k 8080/tcp 2>/dev/null || true

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
Description=SULTAN SSH WebSocket
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

    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/conf.d/sultan-status.conf

    cat >/etc/nginx/conf.d/sultan-status.conf <<EOF
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
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $D;

    ssl_certificate /etc/letsencrypt/live/$D/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$D/privkey.pem;

    location /block {
        return 403 "SULTAN 403 FORBIDDEN";
        add_header Content-Type text/plain;
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

    nginx -t && systemctl enable nginx && systemctl restart nginx

    echo ""
    echo "===== STATUS ====="
    echo -n "Nginx: "; systemctl is-active nginx || true
    echo -n "WebSocket: "; systemctl is-active sultan-ws || true
    echo -n "SSH: "; systemctl is-active ssh || systemctl is-active sshd || true
    pause
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

setting_menu(){
while true; do
refresh_screen
echo -e "${MAG}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${MAG}║${WHITE}              SULTAN SETTING MENU                 ${MAG}║${NC}"
echo -e "${MAG}╚════════════════════════════════════════════════════╝${NC}"
echo -e " ${CYAN}[1]${NC}  Reinstall Nginx              ${CYAN}[16]${NC} Disable Fail2Ban"
echo -e " ${CYAN}[2]${NC}  Disable Nginx                ${CYAN}[17]${NC} Enable BBR"
echo -e " ${CYAN}[3]${NC}  Reinstall HAProxy            ${CYAN}[18]${NC} Disable BBR"
echo -e " ${CYAN}[4]${NC}  Disable HAProxy              ${CYAN}[19]${NC} Restart SSH Only"
echo -e " ${CYAN}[5]${NC}  Reinstall WebSocket          ${CYAN}[20]${NC} Restart Nginx"
echo -e " ${CYAN}[6]${NC}  Disable WebSocket            ${CYAN}[21]${NC} Restart HAProxy"
echo -e " ${CYAN}[7]${NC}  (Disabled to protect menu)   ${CYAN}[22]${NC} Restart Xray"
echo -e " ${CYAN}[8]${NC}  Remove SSL/TLS               ${CYAN}[23]${NC} Restart All Services"
echo -e " ${CYAN}[9]${NC}  Reinstall UDP Custom         ${CYAN}[24]${NC} Change Domain"
echo -e " ${CYAN}[10]${NC} Disable UDP Custom           ${CYAN}[25]${NC} Renew SSL"
echo -e " ${CYAN}[11]${NC} Enable UFW                   ${CYAN}[26]${NC} Reinstall Speedtest"
echo -e " ${CYAN}[12]${NC} Disable UFW                  ${CYAN}[27]${NC} Remove Speedtest"
echo -e " ${CYAN}[13]${NC} Open Ports                   ${CYAN}[28]${NC} VPS Information"
echo -e " ${CYAN}[14]${NC} Close Ports                  ${CYAN}[29]${NC} Fix 403 / 101 / 200 WebSocket"
echo -e " ${CYAN}[15]${NC} Reinstall Fail2Ban"
echo ""
echo -e " ${YELLOW}[0]${NC}  Exit"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -p "Select: " s

case "$s" in
1) reinstall_package_service nginx nginx ;;
2) refresh_screen; systemctl stop nginx 2>/dev/null || true; systemctl disable nginx 2>/dev/null || true; echo "Nginx Disabled"; pause ;;
3) reinstall_package_service haproxy haproxy ;;
4) refresh_screen; systemctl stop haproxy 2>/dev/null || true; systemctl disable haproxy 2>/dev/null || true; echo "HAProxy Disabled"; pause ;;
5) reinstall_websocket ;;
6) refresh_screen; systemctl stop sultan-ws 2>/dev/null || true; systemctl disable sultan-ws 2>/dev/null || true; rm -f /etc/systemd/system/sultan-ws.service; systemctl daemon-reload; echo "WebSocket Disabled"; pause ;;
7) refresh_screen; echo "This option was disabled to protect your main menu installation."; pause ;;
8) remove_ssl ;;
9) reinstall_udp ;;
10) refresh_screen; systemctl stop udp-custom 2>/dev/null || true; systemctl disable udp-custom 2>/dev/null || true; rm -f /etc/systemd/system/udp-custom.service; systemctl daemon-reload; echo "UDP Custom Disabled"; pause ;;
11) refresh_screen; apt install -y ufw; ufw --force enable; echo "UFW Enabled"; pause ;;
12) refresh_screen; ufw disable; echo "UFW Disabled"; pause ;;
13) open_ports ;;
14) close_ports ;;
15) reinstall_fail2ban ;;
16) refresh_screen; systemctl stop fail2ban 2>/dev/null || true; systemctl disable fail2ban 2>/dev/null || true; echo "Fail2Ban Disabled"; pause ;;
17) enable_bbr ;;
18) disable_bbr ;;
19) restart_ssh_safe; pause ;;
20) refresh_screen; systemctl restart nginx 2>/dev/null || true; verify_service nginx; pause ;;
21) refresh_screen; systemctl restart haproxy 2>/dev/null || true; verify_service haproxy; pause ;;
22) refresh_screen; fix_xray_service_root; systemctl restart xray 2>/dev/null || true; systemctl status xray --no-pager -n 20 || true; verify_service xray; pause ;;
23) restart_all_services ;;
24) change_domain ;;
25) renew_ssl ;;
26) reinstall_speedtest ;;
27) refresh_screen; apt remove -y speedtest-cli; echo "Speedtest Removed"; pause ;;
28) vps_info ;;
29) fix_403_ws_status ;;
0) exit 0 ;;
*) setting_menu ;;
esac
done
}

setting_menu
