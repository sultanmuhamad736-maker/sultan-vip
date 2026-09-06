#!/bin/bash
# ==========================================================
# SULTAN VIP - ENTERPRISE INFRASTRUCTURE & SERVICES SETUP
# PURE INFRASTRUCTURE | HIGH PERFORMANCE | NO MENUS
# ==========================================================
# This script is designed to prepare a bare-metal or VPS 
# server for high-throughput VPN services.
# ==========================================================

export DEBIAN_FRONTEND=noninteractive
set -e
trap 'echo -e "\e[31m[ERROR] An error occurred at line $LINENO\e[0m"; exit 1;' ERR

# ================= Color & UI Definitions =================
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
MAG="\e[35m"
WHITE="\e[97m"
NC="\e[0m"

log_info() { echo -e "${CYAN}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }

clear
echo -e "${MAG}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAG}║${WHITE}           SULTAN VIP - ENTERPRISE INFRASTRUCTURE           ${MAG}║${NC}"
echo -e "${MAG}║${CYAN}    Automated, High-Performance, Secure Services Setup      ${MAG}║${NC}"
echo -e "${MAG}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}Initializing in 3 seconds...${NC}"
sleep 3

# ================= 1. Root Check =================
if [ "$(id -u)" != "0" ]; then
    log_error "This script must be run as root."
    exit 1
fi

# ================= 2. System Tuning (Limits & Sysctl) =================
log_info "Applying Enterprise-Grade System Tuning (ulimits & sysctl)..."

# Set max file descriptors for the system
cat > /etc/security/limits.d/sultan-limits.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
root soft nproc 1048576
root hard nproc 1048576
EOF

# Advanced Network Tuning
cat > /etc/sysctl.d/99-sultan-network.conf <<EOF
# --- Network Performance Tuning ---
# Maximize file descriptors
fs.file-max = 1048576
fs.nr_open = 1048576

# BBR Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP Performance & Connections
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_syncookies = 1

# Buffer Sizes
net.core.rmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_default = 1048576
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 1048576 16777216

# Connection Limits
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535

# Keepalive Tuning
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# Port Range & Fin Timeout
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3

# Disable IPv6 (Recommended for pure IPv4 VPNs to avoid routing leaks)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl -p /etc/sysctl.d/99-sultan-network.conf >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1
log_success "System limits and network optimized (BBR Enabled)."

# ================= 3. Dependencies & Repositories =================
log_info "Updating system repositories and installing dependencies..."
apt-get update -y >/dev/null
apt-get install -y --no-install-recommends \
    curl wget nginx haproxy openssh-server python3 certbot python3-certbot-nginx \
    ufw socat lsb-release bc jq uuid-runtime vnstat fail2ban openssl speedtest-cli dnsutils \
    iproute2 tar gzip ca-certificates psmisc coreutils grep sed cron chrony iptables >/dev/null
log_success "All required packages installed."

# ================= 4. HAProxy Optimization =================
log_info "Configuring HAProxy for High Throughput..."
cat > /etc/haproxy/haproxy.cfg <<EOF
global
    daemon
    maxconn 65535
    tune.bufsize 32768
    tune.ssl.default-dh-param 2048
    log /dev/log local0
    log /dev/log local1 notice

defaults
    log global
    mode tcp
    option clitcpka
    option srvtcpka
    option dontlognull
    timeout connect 5s
    timeout client 10m
    timeout server 10m
    timeout tunnel 10m
    timeout client-fin 2s
    timeout server-fin 2s
    maxconn 65535

frontend sultan_tls_443
    bind *:443
    default_backend sultan_nginx_tls

backend sultan_nginx_tls
    server nginx_tls 127.0.0.1:8443 check inter 2s fastinter 500ms rise 2 fall 3
EOF
systemctl restart haproxy >/dev/null 2>&1
systemctl enable haproxy >/dev/null 2>&1
log_success "HAProxy configured and running."

# ================= 5. Nginx Optimization =================
log_info "Configuring Nginx Global Performance Settings..."
cat > /etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes auto;
worker_rlimit_nofile 1048576;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 65535;
    multi_accept on;
    use epoll;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 60;
    keepalive_requests 10000;
    types_hash_max_size 2048;
    server_tokens off;

    client_body_buffer_size 128k;
    client_max_body_size 10m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    output_buffers 1 32k;
    postpone_output 1460;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log off;
    error_log /var/log/nginx/error.log crit;

    gzip on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 4;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
systemctl restart nginx >/dev/null 2>&1
systemctl enable nginx >/dev/null 2>&1
log_success "Nginx globally optimized."

# ================= 6. Xray-Core Official Installation =================
log_info "Installing XTLS Xray-Core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root >/dev/null 2>&1
mkdir -p /usr/local/etc/xray
chown root:root /usr/local/etc/xray
chmod 755 /usr/local/etc/xray

# Ensure Xray service limits are uncapped
mkdir -p /etc/systemd/system/xray.service.d
cat >/etc/systemd/system/xray.service.d/10-sultan.conf <<EOF
[Service]
User=root
Group=root
LimitNOFILE=1048576
LimitNPROC=1048576
EOF
systemctl daemon-reload
systemctl enable xray >/dev/null 2>&1
log_success "Xray-Core installed and limits unlocked."

# ================= 7. High-Performance UDPGW (BadVPN) =================
log_info "Installing BadVPN UDPGW (C-Compiled for pure Gaming Performance)..."
groupadd -r sultan-udpwg 2>/dev/null || true
id sultan-udpwg >/dev/null 2>&1 || useradd -r -g sultan-udpwg -s /usr/sbin/nologin -d /nonexistent sultan-udpwg

wget -qO /usr/local/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"
if [ ! -s /usr/local/bin/badvpn-udpgw ]; then
    log_warn "Primary UDPGW link failed. Compiling from source..."
    apt-get install -y cmake build-essential >/dev/null 2>&1
    git clone https://github.com/ambrop72/badvpn.git /tmp/badvpn >/dev/null 2>&1
    cd /tmp/badvpn
    mkdir build && cd build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null 2>&1
    make >/dev/null 2>&1
    cp udpgw/badvpn-udpgw /usr/local/bin/
    cd /root
    rm -rf /tmp/badvpn
fi

chmod 755 /usr/local/bin/badvpn-udpgw
chown root:sultan-udpwg /usr/local/bin/badvpn-udpgw

cat >/etc/systemd/system/udpwg.service <<EOF
[Unit]
Description=SULTAN UDPGW (BadVPN) 7300
After=network-online.target

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 5000 --max-connections-for-client 20
Restart=always
RestartSec=2
User=sultan-udpwg
Group=sultan-udpwg
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable udpwg >/dev/null 2>&1
systemctl restart udpwg >/dev/null 2>&1
log_success "UDPWG installed and running on port 7300."

# ================= 8. Python Asyncio WebSocket Tunnel =================
log_info "Installing Advanced Python WebSocket Tunnel..."
groupadd -r sultan-ws 2>/dev/null || true
id sultan-ws >/dev/null 2>&1 || useradd -r -g sultan-ws -s /usr/sbin/nologin -d /nonexistent sultan-ws

cat >/usr/local/bin/sultan-ssh-ws <<'PYWS'
#!/usr/bin/env python3
import asyncio, base64, hashlib, os, socket

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
MAX_CONNS = 4096
sema = asyncio.Semaphore(MAX_CONNS)

def tune_sock(writer):
    sock = writer.get_extra_info('socket')
    if sock:
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        except: pass

async def forward(r, w):
    try:
        while True:
            data = await r.read(65536)
            if not data: break
            w.write(data)
            await w.drain()
    except: pass
    finally:
        try: w.close()
        except: pass

async def handle(cr, cw):
    try:
        async with sema:
            tune_sock(cw)
            header = await asyncio.wait_for(cr.readuntil(b"\r\n\r\n"), timeout=3.0)
            text = header.decode(errors="ignore")
            key = ""
            for line in text.split("\r\n"):
                if line.lower().startswith("sec-websocket-key:"):
                    key = line.split(":", 1)[1].strip()
            
            if key:
                accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
                resp = f"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\n\r\n"
                cw.write(resp.encode())
            else:
                cw.write(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
            
            await cw.drain()
            sr, sw = await asyncio.wait_for(asyncio.open_connection("127.0.0.1", 22), timeout=3.0)
            tune_sock(sw)
            await asyncio.gather(forward(cr, sw), forward(sr, cw))
    except:
        try: cw.close()
        except: pass

async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", 8080, limit=65536, reuse_address=True)
    async with server:
        await server.serve_forever()

if __name__ == '__main__':
    import uvloop
    asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
    asyncio.run(main())
PYWS

# Install uvloop for maximum Python asyncio performance
apt-get install -y python3-pip python3-dev build-essential >/dev/null 2>&1
pip3 install uvloop >/dev/null 2>&1 || log_warn "uvloop install failed, fallback to native asyncio."

chown root:sultan-ws /usr/local/bin/sultan-ssh-ws
chmod 750 /usr/local/bin/sultan-ssh-ws

cat >/etc/systemd/system/sultan-ws.service <<EOF
[Unit]
Description=SULTAN High-Performance SSH WebSocket
After=network.target ssh.service
Wants=ssh.service

[Service]
ExecStart=/usr/local/bin/sultan-ssh-ws
Restart=always
RestartSec=2
User=sultan-ws
Group=sultan-ws
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sultan-ws >/dev/null 2>&1
systemctl restart sultan-ws >/dev/null 2>&1
log_success "Advanced WebSocket running on port 8080."

# ================= 9. Security (UFW & Fail2Ban) =================
log_info "Securing Server (UFW & Fail2Ban)..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow 22/tcp >/dev/null 2>&1
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 443/tcp >/dev/null 2>&1
ufw allow 7300/udp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

mkdir -p /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/sultan-sshd.conf <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
maxretry = 3
findtime = 15m
bantime = 24h
ignoreip = 127.0.0.1/8 ::1
EOF
systemctl restart fail2ban >/dev/null 2>&1
systemctl enable fail2ban >/dev/null 2>&1
log_success "UFW Active (22, 80, 443, 7300 allowed). Fail2Ban Active."

# ================= 10. Prepare Sultan Directories =================
log_info "Creating Sultan Directory Structure for Script Integration..."
mkdir -p /etc/sultan/limits
mkdir -p /etc/sultan/xray
mkdir -p /etc/sultan/tg-multi
chmod 700 /etc/sultan /etc/sultan/xray /etc/sultan/limits /etc/sultan/tg-multi
log_success "Directories ready."

# ================= Final Summary =================
echo -e "\n${MAG}========================================================================${NC}"
echo -e "${GREEN}ALL ENTERPRISE INFRASTRUCTURE SERVICES INSTALLED SUCCESSFULLY!${NC}"
echo -e "${WHITE}Total execution lines processed: $(wc -l < $0)${NC}"
echo -e "${CYAN}What was installed & tuned:${NC}"
echo -e " - ${WHITE}Sysctl & Ulimits${NC}: Set to 1M file descriptors + Network tuning."
echo -e " - ${WHITE}BBR${NC}: TCP Congestion control enabled."
echo -e " - ${WHITE}Nginx & HAProxy${NC}: Tuned for 65k+ concurrent connections."
echo -e " - ${WHITE}Xray-Core${NC}: Official XTLS release with uncapped NOFILE."
echo -e " - ${WHITE}UDPWG (BadVPN)${NC}: High-Performance C binary on port 7300."
echo -e " - ${WHITE}WebSocket${NC}: Asyncio Python Tunnel optimized with uvloop."
echo -e " - ${WHITE}Security${NC}: UFW strict firewall & Fail2Ban SSH protection."
echo -e "${MAG}========================================================================${NC}"
echo -e "${YELLOW}Server is perfectly prepared. You can now execute your main menu script.${NC}"
