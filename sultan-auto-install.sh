#!/bin/bash
# ==========================================================
# SULTAN VIP AUTO INSTALL — NO PANEL / NO MENU
# نفس التثبيت التلقائي الموجود في السكربت الأصلي
# الإضافات المطلوبة فقط: HTTP 200 tunnel + auto-repair + UDPGW
# ==========================================================

# Sourcing this installer would apply `set -e` to the parent shell and may
# close the current VPS session. It must run as its own Bash process.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "Do not use source. Run: bash ${BASH_SOURCE[0]} your-domain.com"
  return 1
fi

set -e
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_SUSPEND=1

if [ "$(id -u)" != "0" ]; then
  echo "Run as root."
  exit 1
fi

BASE="/etc/sultan"
XDB="$BASE/xray"
DB="$BASE/users.db"
DOMAIN_FILE="$BASE/domain"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
HTTP200_PORT=8080
UDPGW_VERSION="1.999.130"

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

current_sshd_pid(){
    local P="${PPID:-0}" C NEXT I
    for I in {1..40}; do
        [[ "$P" =~ ^[0-9]+$ ]] || return 1
        [ "$P" -gt 1 ] || return 1
        C="$(cat "/proc/$P/comm" 2>/dev/null || true)"
        if [ "$C" = "sshd" ]; then
            echo "$P"
            return 0
        fi
        NEXT="$(awk '{print $4}' "/proc/$P/stat" 2>/dev/null || true)"
        [ -n "$NEXT" ] && [ "$NEXT" != "$P" ] || return 1
        P="$NEXT"
    done
    return 1
}

current_session_via_tunnel(){
    local REMOTE="${SSH_CONNECTION%% *}"
    case "$REMOTE" in
        127.0.0.1|::1|localhost) return 0 ;;
        *) return 1 ;;
    esac
}

defer_command_until_logout(){
    local NAME="$1" CMD="$2" PID UNIT
    PID="$(current_sshd_pid || true)"
    [[ "$PID" =~ ^[0-9]+$ ]] || return 1
    UNIT="sultan-${NAME}-after-ssh-${PID}"

    # Do not schedule the same deferred action twice during one installation.
    if systemctl cat "$UNIT.service" >/dev/null 2>&1; then
        return 0
    fi

    systemd-run --quiet --collect --unit="$UNIT" /bin/bash -c \
        "while kill -0 $PID 2>/dev/null; do sleep 3; done; $CMD" >/dev/null 2>&1
}

safe_reload_ssh(){
    if ! sshd -t; then
        echo "SSH configuration test failed; reload skipped."
        return 1
    fi
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
}

activate_sultan_ws_safely(){
    systemctl enable sultan-ws >/dev/null 2>&1 || true
    if current_session_via_tunnel; then
        defer_command_until_logout "ws-restart" "systemctl restart sultan-ws" || true
        echo "Current SSH session uses the tunnel; Sultan-WS restart is deferred until logout."
    else
        systemctl restart sultan-ws
    fi
}

activate_proxy_stack_safely(){
    nginx -t
    haproxy -c -f /etc/haproxy/haproxy.cfg
    systemctl enable nginx haproxy >/dev/null 2>&1 || true

    if current_session_via_tunnel; then
        defer_command_until_logout "proxy-reload" \
            "nginx -t && systemctl reload nginx; haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl reload haproxy" || true
        echo "Current SSH session uses the tunnel; proxy reload is deferred until logout."
    else
        if systemctl is-active --quiet nginx 2>/dev/null; then
            systemctl reload nginx || systemctl restart nginx
        else
            systemctl restart nginx
        fi
        if systemctl is-active --quiet haproxy 2>/dev/null; then
            systemctl reload haproxy || systemctl restart haproxy
        else
            systemctl restart haproxy
        fi
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
import asyncio
import base64
import hashlib
import os

LISTEN_HOST = os.environ.get("SULTAN_HTTP_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("SULTAN_HTTP_PORT", "8080"))
SSH_HOST = os.environ.get("SULTAN_SSH_HOST", "127.0.0.1")
SSH_PORT = int(os.environ.get("SULTAN_SSH_PORT", "22"))
MAX_HEADER = 65536
MAX_CONNECTIONS = 256
slots = asyncio.Semaphore(MAX_CONNECTIONS)

async def forward(reader, writer):
    try:
        while True:
            data = await reader.read(16384)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (asyncio.IncompleteReadError, ConnectionError, OSError):
        pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass

def parse_request(header):
    lines = header.decode("latin1", errors="replace").split("\r\n")
    request = lines[0].split()
    if len(request) < 2:
        raise ValueError("invalid request")
    headers = {}
    for line in lines[1:]:
        if not line or ":" not in line:
            continue
        name, value = line.split(":", 1)
        headers[name.strip().lower()] = value.strip()
    return request[0].upper(), request[1], headers

async def handle(client_reader, client_writer):
    ssh_writer = None
    try:
        async with slots:
            header = await asyncio.wait_for(
                client_reader.readuntil(b"\r\n\r\n"), timeout=8
            )
            if len(header) > MAX_HEADER:
                raise ValueError("header too large")

            method, path, headers = parse_request(header)
            is_websocket = (
                headers.get("upgrade", "").lower() == "websocket"
                and "upgrade" in headers.get("connection", "").lower()
                and bool(headers.get("sec-websocket-key", ""))
            )

            # Connect to SSH before replying. This prevents a client from being
            # left stuck after HTTP/1.1 200 OK when sshd is unavailable.
            try:
                ssh_reader, ssh_writer = await asyncio.wait_for(
                    asyncio.open_connection(SSH_HOST, SSH_PORT), timeout=5
                )
            except (asyncio.TimeoutError, ConnectionError, OSError):
                client_writer.write(
                    b"HTTP/1.1 503 Service Unavailable\r\n"
                    b"Connection: close\r\nContent-Length: 0\r\n\r\n"
                )
                await client_writer.drain()
                return

            if is_websocket:
                key = headers["sec-websocket-key"]
                accept = base64.b64encode(
                    hashlib.sha1(
                        (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")
                    ).digest()
                ).decode("ascii")
                client_writer.write(
                    (
                        "HTTP/1.1 101 Switching Protocols\r\n"
                        "Upgrade: websocket\r\n"
                        "Connection: Upgrade\r\n"
                        f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
                    ).encode("ascii")
                )
            else:
                # Direct HTTP compatibility mode on TCP 8080. It deliberately
                # returns the exact status requested, then keeps the same TCP
                # connection open as a raw SSH tunnel.
                client_writer.write(
                    b"HTTP/1.1 200 OK\r\n"
                    b"Connection: keep-alive\r\n"
                    b"Proxy-Agent: SULTAN-SSH-HTTP200\r\n\r\n"
                )
            await client_writer.drain()

            await asyncio.gather(
                forward(client_reader, ssh_writer),
                forward(ssh_reader, client_writer),
            )
    except (asyncio.IncompleteReadError, asyncio.TimeoutError, ConnectionError, OSError, ValueError):
        pass
    finally:
        if ssh_writer is not None:
            try:
                ssh_writer.close()
            except Exception:
                pass
        try:
            client_writer.close()
            await client_writer.wait_closed()
        except Exception:
            pass

async def main():
    server = await asyncio.start_server(
        handle,
        LISTEN_HOST,
        LISTEN_PORT,
        limit=MAX_HEADER,
        reuse_address=True,
    )
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())
PYWS

chmod +x /usr/local/bin/sultan-ssh-ws
cat >/etc/systemd/system/sultan-ws.service <<'EOF'
[Unit]
Description=SULTAN SSH WebSocket and HTTP 200 tunnel
After=network.target ssh.service
Wants=ssh.service
StartLimitIntervalSec=0

[Service]
Environment=SULTAN_HTTP_HOST=0.0.0.0
Environment=SULTAN_HTTP_PORT=8080
Environment=SULTAN_SSH_HOST=127.0.0.1
Environment=SULTAN_SSH_PORT=22
ExecStart=/usr/local/bin/sultan-ssh-ws
Restart=always
RestartSec=2
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
activate_sultan_ws_safely
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

install_badvpn_udpgw_binary(){
    local FOUND WORKDIR ARCHIVE SRC BUILD

    FOUND="$(command -v badvpn-udpgw 2>/dev/null || true)"
    if [ -n "$FOUND" ]; then
        [ "$FOUND" = "/usr/local/bin/badvpn-udpgw" ] || install -m 0755 "$FOUND" /usr/local/bin/badvpn-udpgw
        return 0
    fi

    echo "Building BadVPN UDPGW ${UDPGW_VERSION}..."
    WORKDIR="$(mktemp -d /tmp/sultan-badvpn.XXXXXX)"
    ARCHIVE="$WORKDIR/badvpn.tar.gz"
    curl -fL --retry 3 --connect-timeout 20 \
        "https://github.com/ambrop72/badvpn/archive/refs/tags/${UDPGW_VERSION}.tar.gz" \
        -o "$ARCHIVE"
    tar -xzf "$ARCHIVE" -C "$WORKDIR"
    SRC="$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d -name 'badvpn-*' | head -n1)"
    [ -n "$SRC" ] || { rm -rf "$WORKDIR"; return 1; }
    BUILD="$WORKDIR/build"
    cmake -S "$SRC" -B "$BUILD" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBUILD_NOTHING_BY_DEFAULT=1 \
        -DBUILD_UDPGW=1
    cmake --build "$BUILD" --parallel "$(nproc)"
    install -m 0755 "$BUILD/udpgw/badvpn-udpgw" /usr/local/bin/badvpn-udpgw
    rm -rf "$WORKDIR"
}

reinstall_udp(){
    systemctl stop udp-custom 2>/dev/null || true
    systemctl disable udp-custom 2>/dev/null || true
    rm -f /etc/systemd/system/udp-custom.service

    install_badvpn_udpgw_binary

    cat >/etc/systemd/system/udp-custom.service <<'EOF'
[Unit]
Description=BadVPN UDPGW for SSH game UDP
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 512 --max-connections-for-client 32
Restart=always
RestartSec=2
User=nobody
Group=nogroup
NoNewPrivileges=true
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable udp-custom
    systemctl restart udp-custom
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
    timeout client 7d
    timeout server 7d
    timeout tunnel 7d
    option clitcpka
    option srvtcpka

frontend sultan_tls_443
    bind *:443
    default_backend sultan_nginx_tls

backend sultan_nginx_tls
    server nginx_tls 127.0.0.1:8443 check
EOF

    activate_proxy_stack_safely
}

install_tunnel_autorepair(){
    cat >/usr/local/sbin/sultan-tunnel-health <<'HEALTH'
#!/bin/bash
set -u

probe_http200_tunnel(){
python3 - <<'PYPROBE'
import socket
import sys

try:
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall(
            b"GET /ssh200 HTTP/1.1\r\n"
            b"Host: 127.0.0.1\r\n"
            b"Connection: keep-alive\r\n\r\n"
        )
        data = bytearray()
        while len(data) < 8192 and (b"\r\n\r\n" not in data or b"SSH-" not in data):
            chunk = sock.recv(2048)
            if not chunk:
                break
            data.extend(chunk)
        ok = data.startswith(b"HTTP/1.1 200 OK\r\n") and b"SSH-" in data
        sys.exit(0 if ok else 1)
except OSError:
    sys.exit(1)
PYPROBE
}

ssh_active(){
    systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null
}

restart_ssh(){
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
}

if ! ssh_active; then
    restart_ssh
fi

if ! systemctl is-active --quiet sultan-ws 2>/dev/null; then
    systemctl restart sultan-ws 2>/dev/null || true
fi

if ! probe_http200_tunnel; then
    logger -t sultan-tunnel-health "HTTP 200 tunnel stalled; restarting SSH and sultan-ws"
    restart_ssh
    systemctl restart sultan-ws 2>/dev/null || true
    sleep 2
    probe_http200_tunnel || {
        logger -t sultan-tunnel-health "HTTP 200 tunnel repair failed"
        exit 1
    }
fi

if ! systemctl is-active --quiet udp-custom 2>/dev/null || \
   ! ss -H -ltn 'sport = :7300' 2>/dev/null | grep -q .; then
    systemctl restart udp-custom 2>/dev/null || true
fi

if ! systemctl is-active --quiet nginx 2>/dev/null; then
    nginx -t >/dev/null 2>&1 && systemctl restart nginx 2>/dev/null || true
fi

if ! systemctl is-active --quiet haproxy 2>/dev/null; then
    haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1 && systemctl restart haproxy 2>/dev/null || true
fi
HEALTH
    chmod 700 /usr/local/sbin/sultan-tunnel-health

    cat >/etc/systemd/system/sultan-tunnel-health.service <<'EOF'
[Unit]
Description=SULTAN HTTP 200 and UDPGW self-repair
After=network-online.target ssh.service sultan-ws.service udp-custom.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sultan-tunnel-health
EOF

    cat >/etc/systemd/system/sultan-tunnel-health.timer <<'EOF'
[Unit]
Description=SULTAN tunnel health timer

[Timer]
OnBootSec=20s
OnUnitInactiveSec=30s
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable sultan-tunnel-health.timer >/dev/null 2>&1 || true
    if current_session_via_tunnel; then
        systemctl stop sultan-tunnel-health.timer 2>/dev/null || true
        defer_command_until_logout "health-start" \
            "systemctl start sultan-tunnel-health.timer; /usr/local/sbin/sultan-tunnel-health" || true
        echo "Tunnel health timer will start automatically after logout."
    else
        systemctl start sultan-tunnel-health.timer
    fi
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
    box "HTTP 200 Port" "8080 (TLS OFF)"
    box "UDPGW" "127.0.0.1:7300 via SSH"
    box "VLESS XHTTP" "/vless-xhttp"
    box "VMESS XHTTP" "/vmess-xhttp"
    box "TROJAN XHTTP" "/trojan-xhttp"
    echo ""
    echo "SSH WebSocket Payload:"
    echo "GET / HTTP/1.1[crlf]Host: $D[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf]Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==[crlf]Sec-WebSocket-Version: 13[crlf][crlf]"
    echo ""
    echo "SSH HTTP 200 Payload (connect to $D:8080, SSL/TLS OFF):"
    echo "GET /ssh200 HTTP/1.1[crlf]Host: $D[crlf]Connection: keep-alive[crlf][crlf]"
    echo "Expected Response: HTTP/1.1 200 OK"
    echo ""
    echo "For game UDP, enable UDPGW in the client: 127.0.0.1:7300"
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
    printf "%-16s : [ %s ]\n" "HTTP 200" "$(svc sultan-ws)"
    printf "%-16s : [ %s ]\n" "XHTTP" "$(svc xray)"
    printf "%-16s : [ %s ]\n" "VMESS" "$(svc xray)"
    printf "%-16s : [ %s ]\n" "VLESS" "$(svc xray)"
    printf "%-16s : [ %s ]\n" "TROJAN" "$(svc xray)"
    printf "%-16s : [ %s ]\n" "UDP Custom" "$(svc udp-custom)"
    if current_session_via_tunnel; then
        printf "%-16s : [ DEFERRED ]\n" "Auto Repair"
    else
        printf "%-16s : [ %s ]\n" "Auto Repair" "$(svc sultan-tunnel-health.timer)"
    fi
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

    local D SERVER_IP DOMAIN_IP CERTOK CURRENT_SSH_PORT
    D="${1:-}"

    # An older health timer must not restart the tunnel while this installer
    # is replacing its executable and unit files.
    if current_session_via_tunnel; then
        systemctl stop sultan-tunnel-health.timer 2>/dev/null || true
        echo "Tunnel SSH session detected; disruptive restarts will be deferred."
    fi

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
    apt install -y curl wget nginx haproxy openssh-server python3 certbot ufw socat jq uuid-runtime psmisc openssl ca-certificates dnsutils iproute2 tar gzip lsb-release bc vnstat fail2ban speedtest-cli build-essential cmake

    echo "[2/8] Enabling SSH, Fail2Ban, vnStat and BBR..."
    systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
    safe_reload_ssh || true
    systemctl enable vnstat fail2ban 2>/dev/null || true
    systemctl restart vnstat fail2ban 2>/dev/null || true
    enable_bbr

    echo "[3/8] Opening firewall ports..."
    CURRENT_SSH_PORT="${SSH_CONNECTION##* }"
    [[ "$CURRENT_SSH_PORT" =~ ^[0-9]+$ ]] || CURRENT_SSH_PORT=22
    ufw allow "$CURRENT_SSH_PORT/tcp" 2>/dev/null || true
    ufw allow 22/tcp 2>/dev/null || true
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true
    ufw allow 8080/tcp 2>/dev/null || true
    ufw --force enable 2>/dev/null || true

    echo "[4/8] Preparing SSL certificate..."
    if current_session_via_tunnel; then
        echo "Keeping Nginx/HAProxy running to protect the current SSH tunnel."
    else
        systemctl stop nginx haproxy 2>/dev/null || true
        fuser -k 80/tcp 2>/dev/null || true
        fuser -k 443/tcp 2>/dev/null || true
        fuser -k 8443/tcp 2>/dev/null || true
    fi

    CERTOK=0
    if [ -f "/etc/letsencrypt/live/$D/fullchain.pem" ]; then
        CERTOK=1
    elif [ -n "$DOMAIN_IP" ] && [ "$SERVER_IP" = "$DOMAIN_IP" ] && ! current_session_via_tunnel; then
        certbot certonly --standalone -d "$D" --cert-name "$D" --agree-tos -m "admin@$D" --non-interactive --preferred-challenges http && CERTOK=1 || CERTOK=0
    fi

    if [ "$CERTOK" != "1" ]; then
        echo -e "${YELLOW}Valid Let's Encrypt SSL not issued. Creating self-signed fallback so services can start.${NC}"
        create_self_signed_cert "$D"
    fi

    echo "[5/8] Installing SSH WebSocket and HTTP 200 tunnel..."
    install_sultan_ws_core

    echo "[6/8] Installing Xray and XHTTP configuration..."
    install_xray_core_auto
    write_ready_xray_config

    echo "[7/8] Installing UDPGW for game UDP..."
    reinstall_udp

    echo "[8/8] Configuring Nginx and HAProxy..."
    write_ready_nginx_haproxy "$D"
    install_tunnel_autorepair

    safe_reload_ssh || true
    systemctl restart fail2ban 2>/dev/null || true
    activate_sultan_ws_safely
    systemctl restart xray 2>/dev/null || true
    systemctl restart udp-custom 2>/dev/null || true
    activate_proxy_stack_safely

    if current_session_via_tunnel; then
        echo "Live tunnel health check is deferred until logout to keep this VPS session connected."
    elif ! /usr/local/sbin/sultan-tunnel-health; then
        echo -e "${RED}HTTP 200/UDPGW automatic repair did not pass. Check: journalctl -u sultan-tunnel-health --no-pager${NC}"
        exit 1
    fi

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

#!/bin/bash
# Fix Cloudflare/proxy HTTP 520 while keeping the SULTAN SSH tunnel on WS 101.
# Scope: Sultan-WS, the Nginx TLS WebSocket route, and the tunnel health probe.

set -Eeuo pipefail

if [ "$(id -u)" != "0" ]; then
    echo "Run as root: sudo bash $0"
    exit 1
fi

WS_FILE="/usr/local/bin/sultan-ssh-ws"
NGINX_FILE="/etc/nginx/conf.d/sultan-ready.conf"
HEALTH_FILE="/usr/local/sbin/sultan-tunnel-health"
HEALTH_SERVICE="/etc/systemd/system/sultan-tunnel-health.service"
HEALTH_TIMER="sultan-tunnel-health.timer"

for FILE in "$NGINX_FILE" "$HEALTH_FILE"; do
    if [ ! -f "$FILE" ]; then
        echo "Required file is missing: $FILE"
        exit 1
    fi
done

REMOTE_IP="${SSH_CONNECTION%% *}"
VIA_TUNNEL=0
case "$REMOTE_IP" in
    127.0.0.1|::1|localhost) VIA_TUNNEL=1 ;;
esac

BACKUP_DIR="/etc/sultan/ws101-520-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
[ -f "$WS_FILE" ] && cp -a "$WS_FILE" "$BACKUP_DIR/sultan-ssh-ws"
cp -a "$NGINX_FILE" "$BACKUP_DIR/sultan-ready.conf"
cp -a "$HEALTH_FILE" "$BACKUP_DIR/sultan-tunnel-health"
[ -f "$HEALTH_SERVICE" ] && cp -a "$HEALTH_SERVICE" "$BACKUP_DIR/sultan-tunnel-health.service"

TIMER_WAS_ACTIVE=0
if systemctl is-active --quiet "$HEALTH_TIMER" 2>/dev/null; then
    TIMER_WAS_ACTIVE=1
fi
systemctl stop "$HEALTH_TIMER" 2>/dev/null || true

ROLLBACK=1
rollback_on_error(){
    local STATUS=$?
    if [ "$ROLLBACK" = "1" ]; then
        [ -f "$BACKUP_DIR/sultan-ssh-ws" ] && cp -a "$BACKUP_DIR/sultan-ssh-ws" "$WS_FILE"
        cp -a "$BACKUP_DIR/sultan-ready.conf" "$NGINX_FILE"
        cp -a "$BACKUP_DIR/sultan-tunnel-health" "$HEALTH_FILE"
        [ -f "$BACKUP_DIR/sultan-tunnel-health.service" ] && \
            cp -a "$BACKUP_DIR/sultan-tunnel-health.service" "$HEALTH_SERVICE"
        systemctl daemon-reload 2>/dev/null || true
        nginx -t >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null || true
        if [ "$VIA_TUNNEL" = "0" ]; then
            systemctl restart sultan-ws 2>/dev/null || true
        fi
        [ "$TIMER_WAS_ACTIVE" = "1" ] && systemctl start "$HEALTH_TIMER" 2>/dev/null || true
        echo "The 520 repair failed; the original files were restored."
    fi
    exit "$STATUS"
}
trap rollback_on_error ERR INT TERM

# Keep the tunnel response on WS101 and never return HTTP 200/403/426 from the
# Sultan-WS backend. HTTP/1.1 at the Nginx origin remains the targeted 520 fix.
cat >"$WS_FILE" <<'PYWS'
#!/usr/bin/env python3
import asyncio
import base64
import hashlib
import os

LISTEN_HOST = os.environ.get("SULTAN_HTTP_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("SULTAN_HTTP_PORT", "8080"))
SSH_HOST = os.environ.get("SULTAN_SSH_HOST", "127.0.0.1")
SSH_PORT = int(os.environ.get("SULTAN_SSH_PORT", "22"))
MAX_HEADER = 65536
MAX_CONNECTIONS = 256
slots = asyncio.Semaphore(MAX_CONNECTIONS)


async def close_writer(writer):
    try:
        writer.close()
        await writer.wait_closed()
    except Exception:
        pass


async def forward(reader, writer):
    try:
        while True:
            data = await reader.read(16384)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (asyncio.IncompleteReadError, ConnectionError, OSError):
        pass
    finally:
        await close_writer(writer)


def parse_request(header):
    lines = header.decode("latin1", errors="replace").split("\r\n")
    request = lines[0].split()
    if len(request) < 3:
        raise ValueError("invalid request line")
    headers = {}
    for line in lines[1:]:
        if not line or ":" not in line:
            continue
        name, value = line.split(":", 1)
        headers[name.strip().lower()] = value.strip()
    return request[0].upper(), request[1], headers


async def send_http_error(writer, status, extra=b""):
    writer.write(
        f"HTTP/1.1 {status}\r\n".encode("ascii")
        + b"Connection: close\r\n"
        + extra
        + b"Content-Length: 0\r\n\r\n"
    )
    await writer.drain()


async def handle(client_reader, client_writer):
    ssh_writer = None
    try:
        async with slots:
            header = await asyncio.wait_for(
                client_reader.readuntil(b"\r\n\r\n"), timeout=10
            )
            if len(header) > MAX_HEADER:
                await send_http_error(client_writer, "431 Request Header Fields Too Large")
                return

            _method, _path, headers = parse_request(header)
            key = headers.get(
                "sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ=="
            )

            try:
                ssh_reader, ssh_writer = await asyncio.wait_for(
                    asyncio.open_connection(SSH_HOST, SSH_PORT), timeout=5
                )
            except (asyncio.TimeoutError, ConnectionError, OSError):
                await send_http_error(client_writer, "503 Service Unavailable")
                return

            accept = base64.b64encode(
                hashlib.sha1(
                    (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")
                ).digest()
            ).decode("ascii")
            client_writer.write(
                (
                    "HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
                ).encode("ascii")
            )
            await client_writer.drain()

            await asyncio.gather(
                forward(client_reader, ssh_writer),
                forward(ssh_reader, client_writer),
            )
    except (
        asyncio.IncompleteReadError,
        asyncio.LimitOverrunError,
        asyncio.TimeoutError,
        ConnectionError,
        OSError,
        ValueError,
    ):
        pass
    finally:
        if ssh_writer is not None:
            await close_writer(ssh_writer)
        await close_writer(client_writer)


async def main():
    server = await asyncio.start_server(
        handle,
        LISTEN_HOST,
        LISTEN_PORT,
        limit=MAX_HEADER,
        reuse_address=True,
    )
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
PYWS
chmod 755 "$WS_FILE"

# Keep the origin side on HTTP/1.1 for a classic WebSocket 101 handshake.
# Only the TLS catch-all SSH/WS route is replaced; XHTTP locations stay intact.
python3 - "$NGINX_FILE" <<'PYNGINX'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()


def block_end(source, start):
    opening = source.find("{", start)
    if opening < 0:
        raise SystemExit("Malformed Nginx block")
    depth = 0
    for index in range(opening, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index + 1
    raise SystemExit("Unclosed Nginx block")


tls_match = re.search(
    r"server\s*\{\s*listen\s+127\.0\.0\.1:8443\s+ssl(?:\s+http2)?\s*;",
    text,
)
if not tls_match:
    raise SystemExit("Could not locate the Sultan TLS server block")

tls_start = tls_match.start()
tls_end = block_end(text, tls_start)
tls = text[tls_start:tls_end]
tls = re.sub(
    r"listen\s+127\.0\.0\.1:8443\s+ssl(?:\s+http2)?\s*;",
    "listen 127.0.0.1:8443 ssl;",
    tls,
    count=1,
)
tls = re.sub(r"^\s*http2\s+on\s*;\s*$", "", tls, flags=re.M)

# Remove the deliberate TLS /block 403 route if an older config still has it.
block_marker = re.search(r"\n\s{4}location\s+/block\s*\{", tls)
if block_marker:
    start = block_marker.start() + 1
    end = block_end(tls, start)
    tls = tls[:start] + tls[end:]

root_match = re.search(r"\n\s{4}location\s+/\s*\{", tls)
if not root_match:
    raise SystemExit("Could not locate the Sultan TLS root location")
root_start = root_match.start() + 1
root_end = block_end(tls, root_start)

new_root = '''    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade "websocket";
        proxy_set_header Connection "Upgrade";
        proxy_set_header Sec-WebSocket-Key $http_sec_websocket_key;
        proxy_set_header Sec-WebSocket-Version $http_sec_websocket_version;
        proxy_set_header Host $host;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }'''

tls = tls[:root_start] + new_root + tls[root_end:]
text = text[:tls_start] + tls + text[tls_end:]
path.write_text(text)
PYNGINX

cat >"$HEALTH_FILE" <<'HEALTH'
#!/bin/bash
set -u

probe_ws101_tunnel(){
python3 - <<'PYPROBE'
import socket
import sys

request = (
    b"GET / HTTP/1.1\r\n"
    b"Host: 127.0.0.1\r\n"
    b"Upgrade: websocket\r\n"
    b"Connection: Upgrade\r\n"
    b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
    b"Sec-WebSocket-Version: 13\r\n\r\n"
)
try:
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall(request)
        data = bytearray()
        while len(data) < 8192 and (b"\r\n\r\n" not in data or b"SSH-" not in data):
            chunk = sock.recv(2048)
            if not chunk:
                break
            data.extend(chunk)
        ok = (
            data.startswith(b"HTTP/1.1 101 Switching Protocols\r\n")
            and b"Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n" in data
            and b"SSH-" in data
        )
        sys.exit(0 if ok else 1)
except OSError:
    sys.exit(1)
PYPROBE
}

ssh_active(){
    systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null
}

start_ssh(){
    systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null || true
}

if ! ssh_active; then
    start_ssh
fi

if ! systemctl is-active --quiet sultan-ws 2>/dev/null; then
    systemctl restart sultan-ws 2>/dev/null || true
fi

if ! probe_ws101_tunnel; then
    logger -t sultan-tunnel-health "WebSocket 101 tunnel failed; restarting sultan-ws"
    systemctl restart sultan-ws 2>/dev/null || true
    sleep 2
    probe_ws101_tunnel || {
        logger -t sultan-tunnel-health "WebSocket 101 repair failed"
        exit 1
    }
fi

if ! systemctl is-active --quiet udp-custom 2>/dev/null || \
   ! ss -H -ltn 'sport = :7300' 2>/dev/null | grep -q .; then
    systemctl restart udp-custom 2>/dev/null || true
fi

if ! systemctl is-active --quiet nginx 2>/dev/null; then
    nginx -t >/dev/null 2>&1 && systemctl restart nginx 2>/dev/null || true
fi

if ! systemctl is-active --quiet haproxy 2>/dev/null; then
    haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1 && \
        systemctl restart haproxy 2>/dev/null || true
fi
HEALTH
chmod 700 "$HEALTH_FILE"

if [ -f "$HEALTH_SERVICE" ]; then
    sed -i \
        's/^Description=.*/Description=SULTAN WebSocket 101 and UDPGW self-repair/' \
        "$HEALTH_SERVICE"
fi

python3 -m py_compile "$WS_FILE"
bash -n "$HEALTH_FILE"
nginx -t
systemctl daemon-reload
systemctl reload nginx

current_sshd_pid(){
    local P="${PPID:-0}" C NEXT I
    for I in {1..40}; do
        [[ "$P" =~ ^[0-9]+$ ]] || return 1
        [ "$P" -gt 1 ] || return 1
        C="$(cat "/proc/$P/comm" 2>/dev/null || true)"
        if [ "$C" = "sshd" ]; then
            echo "$P"
            return 0
        fi
        NEXT="$(awk '{print $4}' "/proc/$P/stat" 2>/dev/null || true)"
        [ -n "$NEXT" ] && [ "$NEXT" != "$P" ] || return 1
        P="$NEXT"
    done
    return 1
}

if [ "$VIA_TUNNEL" = "1" ]; then
    SSHD_PID="$(current_sshd_pid || true)"
    if [[ "$SSHD_PID" =~ ^[0-9]+$ ]]; then
        UNIT="sultan-ws520-after-ssh-${SSHD_PID}"
        systemd-run --quiet --collect --unit="$UNIT" /bin/bash -c \
            "while kill -0 $SSHD_PID 2>/dev/null; do sleep 3; done; systemctl restart sultan-ws; systemctl start $HEALTH_TIMER; sleep 2; $HEALTH_FILE || true"
        echo "The 520 fix is installed. It will activate after this SSH session logs out."
    else
        systemd-run --quiet --collect --on-active=10s \
            --unit="sultan-ws520-delayed-$$" /bin/bash -c \
            "systemctl restart sultan-ws; systemctl start $HEALTH_TIMER; sleep 2; $HEALTH_FILE || true"
        echo "The 520 fix is installed. The tunnel will restart once in 10 seconds."
    fi
else
    systemctl restart sultan-ws
    systemctl start "$HEALTH_TIMER"
    sleep 2
    "$HEALTH_FILE"
    echo "WS101 is active and the local health check passed."
fi

ROLLBACK=0
trap - ERR INT TERM
echo "Backup: $BACKUP_DIR"
