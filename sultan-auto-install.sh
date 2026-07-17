#!/bin/bash
# ==========================================================
# SULTAN VIP AUTO INSTALL — NO PANEL / NO MENU
# نفس التثبيت التلقائي الموجود في السكربت الأصلي
# تم حذف واجهة اللوحة والقوائم فقط
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
XRAY_CONFIG="/usr/local/etc/xray/config.json"

mkdir -p "$BASE" "$XDB"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
NC="\e[0m"

box(){ printf "%-16s :      [ %s ]\n" "$1" "$2"; }
svc(){ systemctl is-active --quiet "$1" 2>/dev/null && echo "ACTIVE" || echo "OFFLINE"; }
get_domain(){ cat "$DOMAIN_FILE" 2>/dev/null || echo "Not Set"; }
get_ip(){ local IP; IP="$(curl -s --max-time 4 ipv4.icanhazip.com 2>/dev/null | tr -d '\n')"; [ -n "$IP" ] && echo "$IP" || hostname -I | awk '{print $1}'; }

tls_status(){
    local D
    D="$(get_domain)"
    if [ -f "/etc/letsencrypt/live/$D/fullchain.pem" ] || [ -f "/etc/sultan/selfsigned/$D/fullchain.pem" ]; then
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
    if systemctl is-active --quiet nginx 2>/dev/null \
       && systemctl is-active --quiet haproxy 2>/dev/null \
       && systemctl is-active --quiet sultan-ws 2>/dev/null \
       && systemctl is-active --quiet xray 2>/dev/null; then
        echo READY
    else
        echo "NEEDS CHECK"
    fi
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

install_xray_core_auto(){
    if command -v xray >/dev/null 2>&1 || [ -x /usr/local/bin/xray ]; then
        return
    fi
    echo "Installing Xray core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

create_self_signed_cert(){
    local D="$1"
    mkdir -p "/etc/sultan/selfsigned/$D"
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout "/etc/sultan/selfsigned/$D/privkey.pem" \
        -out "/etc/sultan/selfsigned/$D/fullchain.pem" \
        -subj "/CN=$D" >/dev/null 2>&1
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
cat >/etc/systemd/system/sultan-ws.service <<'EOF'
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
    mkdir -p /usr/local/etc/xray
    cat >/usr/local/etc/xray/config.json <<'EOF'
{"log":{"loglevel":"warning"},"inbounds":[{"tag":"vless-xhttp","listen":"127.0.0.1","port":10000,"protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"xhttp","security":"none","xhttpSettings":{"path":"/vless-xhttp"}}},{"tag":"vmess-xhttp","listen":"127.0.0.1","port":10085,"protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"xhttp","security":"none","xhttpSettings":{"path":"/vmess-xhttp"}}},{"tag":"trojan-xhttp","listen":"127.0.0.1","port":10086,"protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"xhttp","security":"none","xhttpSettings":{"path":"/trojan-xhttp"}}}],"outbounds":[{"protocol":"freedom"}]}
EOF
    fix_xray_service_root
    if [ -x /usr/local/bin/xray ]; then
        /usr/local/bin/xray run -test -config "$XRAY_CONFIG"
    elif command -v xray >/dev/null 2>&1; then
        xray run -test -config "$XRAY_CONFIG"
    fi
    systemctl enable xray 2>/dev/null || true
    systemctl restart xray 2>/dev/null || true
}

reinstall_udp(){
    systemctl stop udp-custom 2>/dev/null || true
    systemctl disable udp-custom 2>/dev/null || true
    rm -f /etc/systemd/system/udp-custom.service
    apt-get update -y
    apt-get install -y socat
    cat >/etc/systemd/system/udp-custom.service <<'EOF'
[Unit]
Description=UDP Custom 7300
After=network.target

[Service]
ExecStart=/usr/bin/socat UDP-LISTEN:7300,fork UDP:127.0.0.1:7300
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable udp-custom
    systemctl restart udp-custom
    ufw allow 7300/udp 2>/dev/null || true
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

    cat >/etc/haproxy/haproxy.cfg <<'EOF'
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
    haproxy -c -f /etc/haproxy/haproxy.cfg
    systemctl enable nginx haproxy
    systemctl restart nginx
    systemctl restart haproxy
}

enable_bbr(){
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p || true
}

show_payloads(){
    local D
    D="$(get_domain)"
    [ "$D" = "Not Set" ] && D="$(get_ip)"
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
}

show_status(){
    echo ""
    echo "=========================================="
    printf "%-16s : [ %s ]\n" "TLS / SSL" "$(tls_status)"
    printf "%-16s : [ %s ]\n" "WebSocket" "$(svc sultan-ws)"
    printf "%-16s : [ %s ]\n" "XHTTP" "$(svc xray)"
    printf "%-16s : [ %s ]\n" "VMESS" "$(svc xray)"
    printf "%-16s : [ %s ]\n" "VLESS" "$(svc xray)"
    printf "%-16s : [ %s ]\n" "TROJAN" "$(svc xray)"
    printf "%-16s : [ %s ]\n" "UDP Custom" "$(svc udp-custom)"
    printf "%-16s : [ %s ]\n" "Nginx" "$(svc nginx)"
    printf "%-16s : [ %s ]\n" "HAProxy" "$(svc haproxy)"
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        printf "%-16s : [ ACTIVE ]\n" "SSH"
    else
        printf "%-16s : [ OFFLINE ]\n" "SSH"
    fi
    printf "%-16s : [ %s ]\n" "Fail2Ban" "$(svc fail2ban)"
    printf "%-16s : [ %s ]\n" "BBR" "$(bbr_status)"
    printf "%-16s : [ %s ]\n" "Core Status" "$(core_status)"
    echo "=========================================="
}

setup_ready_ssl_ws_xhttp(){
    echo "==================================="
    echo "   READY SSL/TLS + SNI + WS + XHTTP"
    echo "==================================="

    local D SERVER_IP DOMAIN_IP CERTOK
    D="${1:-}"

    if [ -z "$D" ]; then
        D="$(get_domain)"
    fi

    if [ "$D" = "Not Set" ] || [ -z "$D" ]; then
        read -p "Enter domain for SSL/SNI: " D
    fi

    if [ -z "$D" ]; then
        echo "Domain is required."
        exit 1
    fi

    echo "$D" > "$DOMAIN_FILE"

    SERVER_IP="$(get_ip)"
    DOMAIN_IP="$(getent ahostsv4 "$D" | awk '{print $1; exit}')"
    box "Server IP" "$SERVER_IP"
    box "Domain IP" "${DOMAIN_IP:-EMPTY}"

    echo "[1/8] Installing required packages..."
    apt update -y
    apt install -y curl wget nginx haproxy openssh-server python3 certbot ufw socat jq uuid-runtime psmisc openssl ca-certificates dnsutils iproute2 tar gzip lsb-release bc vnstat fail2ban speedtest-cli

    echo "[2/8] Enabling SSH, Fail2Ban, vnStat and BBR..."
    systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    systemctl enable vnstat fail2ban 2>/dev/null || true
    systemctl restart vnstat fail2ban 2>/dev/null || true
    enable_bbr

    echo "[3/8] Opening firewall ports..."
    ufw allow 22/tcp 2>/dev/null || true
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true
    ufw allow 7300/udp 2>/dev/null || true
    ufw --force enable 2>/dev/null || true

    echo "[4/8] Preparing SSL certificate..."
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

    echo "[5/8] Installing SSH WebSocket..."
    install_sultan_ws_core

    echo "[6/8] Installing Xray and XHTTP configuration..."
    install_xray_core_auto
    write_ready_xray_config

    echo "[7/8] Installing UDP Custom..."
    reinstall_udp

    echo "[8/8] Configuring Nginx and HAProxy..."
    write_ready_nginx_haproxy "$D"

    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    systemctl restart fail2ban 2>/dev/null || true
    systemctl restart sultan-ws 2>/dev/null || true
    systemctl restart xray 2>/dev/null || true
    systemctl restart udp-custom 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || true
    systemctl restart haproxy 2>/dev/null || true

    show_status
    show_payloads

    echo "===== PORTS ====="
    ss -tulpn | grep -E ':22|:80|:443|:7300|:8080|:8443|:10000|:10085|:10086' || true
}

echo "==========================================="
echo "       SULTAN VIP AUTOMATIC INSTALL"
echo "       NO PANEL / NO MENU"
echo "==========================================="

setup_ready_ssl_ws_xhttp "${1:-}"
