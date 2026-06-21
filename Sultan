#!/usr/bin/env bash
# SULTAN VIP SERVER - V2RAY + DNS + OPTIONAL WEBSOCKET
# GitHub-ready mini installer
# Core: V2Ray + DNS
# Optional: WebSocket + HAProxy 443 + Nginx 80 from Setting menu

set +e

BASE="/etc/sultan"
DOMAIN_FILE="$BASE/domain"
XDB="$BASE/xray"
DNSDB="$BASE/dns/records.db"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
DNSCONF="/etc/dnsmasq.d/sultan-v2ray-dns.conf"

VLESS_TCP_PORT=443
VMESS_TCP_PORT=8443
TROJAN_TCP_PORT=2083

VLESS_WS_PORT=10000
VMESS_WS_PORT=10085
TROJAN_WS_PORT=10086

VLESS_WS_PATH="/vless-ws"
VMESS_WS_PATH="/vmess-ws"
TROJAN_WS_PATH="/trojan-ws"

R='\033[1;31m'
G='\033[1;32m'
Y='\033[1;33m'
B='\033[1;34m'
C='\033[1;36m'
P='\033[1;35m'
W='\033[1;37m'
N='\033[0m'

mkdir -p "$BASE" "$XDB" "$(dirname "$DNSDB")"
touch "$DNSDB"

pause(){ echo; read -rp "Enter..." _; }
ip(){ curl -4 -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}'; }
domain(){ [ -s "$DOMAIN_FILE" ] && cat "$DOMAIN_FILE" || echo "Not Set"; }
svc(){ systemctl is-active "$1" 2>/dev/null || echo "off"; }

headx(){
  clear 2>/dev/null
  echo -e "${P}╔════════════════════════════════════════════╗${N}"
  echo -e "${P}║${W}              SULTAN VIP SERVER             ${P}║${N}"
  echo -e "${P}║${W}          V2RAY + DNS + WEBSOCKET        ${P}║${N}"
  echo -e "${P}║${W}        DNS CORE | WS OPTIONAL | TLS     ${P}║${N}"
  echo -e "${P}╚════════════════════════════════════════════╝${N}"
  printf "${B}Domain${N}: ${W}%s${N}\n" "$(domain)"
  printf "${B}IP${N}: ${W}%s${N}\n" "$(ip)"
  printf "${B}Xray${N}: ${W}%s${N} | ${B}DNS${N}: ${W}%s${N} | ${B}HAProxy${N}: ${W}%s${N} | ${B}Nginx${N}: ${W}%s${N}\n" "$(svc xray)" "$(svc dnsmasq)" "$(svc haproxy)" "$(svc nginx)"
  echo -e "${P}────────────────────────────────────────────${N}"
}

install_menu_cmd(){
  cp "$0" /usr/local/bin/menu 2>/dev/null || true
  chmod +x /usr/local/bin/menu 2>/dev/null || true
}

install_deps(){
  headx
  echo -e "${Y}Installing packages...${N}"
  apt update -y
  apt install -y curl wget unzip jq uuid-runtime openssl ca-certificates certbot \
    dnsmasq dnsutils nginx haproxy ufw psmisc iproute2 lsof
  systemctl enable dnsmasq nginx 2>/dev/null || true
  echo -e "${G}Packages installed.${N}"
  pause
}

install_xray(){
  headx
  echo -e "${Y}Installing Xray...${N}"
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  systemctl enable xray 2>/dev/null || true
  echo -e "${G}Xray installed.${N}"
  pause
}

set_domain(){
  headx
  read -rp "Domain: " d
  [ -z "$d" ] && return
  echo "$d" > "$DOMAIN_FILE"
  echo -e "${G}Saved: $d${N}"
  pause
}

ssl_issue(){
  headx
  d="$(domain)"
  [ "$d" = "Not Set" ] && echo "Set domain first." && pause && return
  systemctl stop nginx haproxy xray 2>/dev/null || true
  fuser -k 80/tcp 2>/dev/null || true
  certbot certonly --standalone -d "$d" --cert-name "$d" --agree-tos -m "admin@$d" --non-interactive --preferred-challenges http
  systemctl restart nginx 2>/dev/null || true
  pause
}

cert(){
  d="$(domain)"
  if [ -f "/etc/letsencrypt/live/$d/fullchain.pem" ]; then
    echo "/etc/letsencrypt/live/$d/fullchain.pem"
  else
    echo "/etc/sultan/$d.crt"
  fi
}

key(){
  d="$(domain)"
  if [ -f "/etc/letsencrypt/live/$d/privkey.pem" ]; then
    echo "/etc/letsencrypt/live/$d/privkey.pem"
  else
    echo "/etc/sultan/$d.key"
  fi
}

ensure_cert(){
  d="$(domain)"
  [ "$d" = "Not Set" ] && d="$(ip)"
  c="$(cert)"
  k="$(key)"
  if [ ! -f "$c" ] || [ ! -f "$k" ]; then
    mkdir -p /etc/sultan
    openssl req -x509 -nodes -newkey rsa:2048 -keyout "$k" -out "$c" -days 3650 -subj "/CN=$d" >/dev/null 2>&1
  fi
}

dns_apply(){
  headx
  d="$(domain)"
  [ "$d" = "Not Set" ] && d="local.sultan"
  myip="$(ip)"

  cat >"$DNSCONF" <<EOF
port=53
domain-needed
bogus-priv
no-resolv
server=1.1.1.1
server=8.8.8.8
server=9.9.9.9
cache-size=10000
address=/$d/$myip
EOF

  while IFS='|' read -r type name val; do
    [ -z "$type" ] && continue
    if [ "$name" = "@" ]; then
      fqdn="$d"
    elif [ "$name" = "*" ]; then
      fqdn="$d"
    elif echo "$name" | grep -q '\.'; then
      fqdn="$name"
    else
      fqdn="$name.$d"
    fi

    if [ "$type" = "A" ]; then
      [ "$name" = "*" ] && echo "address=/$d/$val" >>"$DNSCONF" || echo "address=/$fqdn/$val" >>"$DNSCONF"
    fi

    if [ "$type" = "CNAME" ]; then
      echo "cname=$fqdn,$val" >>"$DNSCONF"
    fi
  done < "$DNSDB"

  systemctl stop systemd-resolved 2>/dev/null || true
  systemctl disable systemd-resolved 2>/dev/null || true
  echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" >/etc/resolv.conf

  fuser -k 53/tcp 2>/dev/null || true
  fuser -k 53/udp 2>/dev/null || true

  dnsmasq --test --conf-file="$DNSCONF" && systemctl enable dnsmasq >/dev/null 2>&1 && systemctl restart dnsmasq

  ufw allow 53/tcp 2>/dev/null || true
  ufw allow 53/udp 2>/dev/null || true

  echo -e "${G}DNS applied on port 53.${N}"
  pause
}

dns_record(){
  headx
  echo "[1] A"
  echo "[2] CNAME"
  echo "[3] Wildcard A"
  read -rp "Type: " t
  case "$t" in
    1) type=A; read -rp "Name (@/sub): " name; read -rp "IP: " val ;;
    2) type=CNAME; read -rp "Name: " name; read -rp "Target: " val ;;
    3) type=A; name="*"; read -rp "IP: " val ;;
    *) return ;;
  esac
  [ -n "$name" ] && [ -n "$val" ] && echo "$type|$name|$val" >> "$DNSDB"
  dns_apply
}

clients_json(){
python3 - <<PY
import json, os
xdb="$XDB"
def rd(p):
    f=os.path.join(xdb,p+".db")
    a=[]
    if not os.path.exists(f):
        return a
    for line in open(f,errors="ignore"):
        x=line.strip().split("|")
        if len(x)<2:
            continue
        u,v=x[0],x[1]
        if p=="vless":
            a.append({"id":v,"email":u})
        elif p=="vmess":
            a.append({"id":v,"alterId":0,"email":u})
        elif p=="trojan":
            a.append({"password":v,"email":u})
    return a
print(json.dumps({"vless":rd("vless"),"vmess":rd("vmess"),"trojan":rd("trojan")}))
PY
}

xray_tcp_apply(){
  headx
  d="$(domain)"
  [ "$d" = "Not Set" ] && echo "Set domain first." && pause && return
  command -v xray >/dev/null 2>&1 || { echo "Install Xray first."; pause; return; }

  ensure_cert
  c="$(cert)"
  k="$(key)"
  cj="$(clients_json)"
  vl="$(echo "$cj" | jq -c .vless)"
  vm="$(echo "$cj" | jq -c .vmess)"
  tr="$(echo "$cj" | jq -c .trojan)"

  systemctl stop haproxy 2>/dev/null || true
  systemctl disable haproxy 2>/dev/null || true

  mkdir -p /usr/local/etc/xray
  cat >"$XRAY_CONFIG" <<EOF
{
  "log":{"loglevel":"warning"},
  "dns":{"servers":["https+local://1.1.1.1/dns-query","https+local://8.8.8.8/dns-query","localhost"],"queryStrategy":"UseIP"},
  "inbounds":[
    {"tag":"vless-tcp-tls","listen":"0.0.0.0","port":$VLESS_TCP_PORT,"protocol":"vless","settings":{"clients":$vl,"decryption":"none"},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"$d","certificates":[{"certificateFile":"$c","keyFile":"$k"}],"alpn":["http/1.1"]}}},
    {"tag":"vmess-tcp-tls","listen":"0.0.0.0","port":$VMESS_TCP_PORT,"protocol":"vmess","settings":{"clients":$vm},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"$d","certificates":[{"certificateFile":"$c","keyFile":"$k"}],"alpn":["http/1.1"]}}},
    {"tag":"trojan-tcp-tls","listen":"0.0.0.0","port":$TROJAN_TCP_PORT,"protocol":"trojan","settings":{"clients":$tr},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"$d","certificates":[{"certificateFile":"$c","keyFile":"$k"}],"alpn":["http/1.1"]}}}
  ],
  "outbounds":[{"tag":"direct","protocol":"freedom","settings":{"domainStrategy":"UseIP"}},{"tag":"block","protocol":"blackhole"}],
  "routing":{"domainStrategy":"IPIfNonMatch","rules":[{"type":"field","outboundTag":"block","protocol":["bittorrent"]}]}
}
EOF

  xray run -test -config "$XRAY_CONFIG" && systemctl enable xray >/dev/null 2>&1 && systemctl restart xray
  echo -e "${G}V2Ray TCP/TLS + DNS applied.${N}"
  pause
}

xray_ws_apply(){
  headx
  d="$(domain)"
  [ "$d" = "Not Set" ] && echo "Set domain first." && pause && return
  command -v xray >/dev/null 2>&1 || { echo "Install Xray first."; pause; return; }

  cj="$(clients_json)"
  vl="$(echo "$cj" | jq -c .vless)"
  vm="$(echo "$cj" | jq -c .vmess)"
  tr="$(echo "$cj" | jq -c .trojan)"

  mkdir -p /usr/local/etc/xray
  cat >"$XRAY_CONFIG" <<EOF
{
  "log":{"loglevel":"warning"},
  "dns":{"servers":["https+local://1.1.1.1/dns-query","https+local://8.8.8.8/dns-query","localhost"],"queryStrategy":"UseIP"},
  "inbounds":[
    {"tag":"vless-ws","listen":"127.0.0.1","port":$VLESS_WS_PORT,"protocol":"vless","settings":{"clients":$vl,"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"$VLESS_WS_PATH"}}},
    {"tag":"vmess-ws","listen":"127.0.0.1","port":$VMESS_WS_PORT,"protocol":"vmess","settings":{"clients":$vm},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"$VMESS_WS_PATH"}}},
    {"tag":"trojan-ws","listen":"127.0.0.1","port":$TROJAN_WS_PORT,"protocol":"trojan","settings":{"clients":$tr},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"$TROJAN_WS_PATH"}}}
  ],
  "outbounds":[{"tag":"direct","protocol":"freedom","settings":{"domainStrategy":"UseIP"}},{"tag":"block","protocol":"blackhole"}],
  "routing":{"domainStrategy":"IPIfNonMatch","rules":[{"type":"field","outboundTag":"block","protocol":["bittorrent"]}]}
}
EOF

  xray run -test -config "$XRAY_CONFIG" && systemctl enable xray >/dev/null 2>&1 && systemctl restart xray
  echo -e "${G}V2Ray WebSocket + DNS applied. Now install HAProxy/Nginx from Setting.${N}"
  pause
}

nginx80(){
  headx
  d="$(domain)"
  [ "$d" = "Not Set" ] && d="_"
  rm -f /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/*
  cat >/etc/nginx/conf.d/sultan-80.conf <<EOF
server {
 listen 80;
 listen [::]:80;
 server_name $d;
 location / { return 200 "SULTAN VIP SERVER V2RAY DNS OK"; add_header Content-Type text/plain; }
 location /ok { return 200 "SULTAN 200 OK"; add_header Content-Type text/plain; }
 location /block { return 403 "SULTAN 403"; add_header Content-Type text/plain; }
}
EOF
  nginx -t && systemctl enable nginx >/dev/null 2>&1 && systemctl restart nginx
  echo -e "${G}Nginx 80 installed/configured.${N}"
  pause
}

haproxy443(){
  headx
  d="$(domain)"
  [ "$d" = "Not Set" ] && echo "Set domain first." && pause && return

  ensure_cert
  c="$(cert)"
  k="$(key)"
  hp="/etc/haproxy/certs/$d.pem"
  mkdir -p /etc/haproxy/certs
  cat "$c" "$k" > "$hp"
  chmod 600 "$hp"

  cat >/etc/haproxy/haproxy.cfg <<EOF
global
    daemon
    maxconn 20000

defaults
    mode http
    option httplog
    timeout connect 10s
    timeout client  2h
    timeout server  2h
    timeout tunnel  2h

frontend sultan_443_ws
    bind *:443 ssl crt $hp alpn http/1.1

    acl is_ok path /ok
    acl is_block path /block
    acl is_vless path_beg $VLESS_WS_PATH
    acl is_vmess path_beg $VMESS_WS_PATH
    acl is_trojan path_beg $TROJAN_WS_PATH

    http-request return status 200 content-type text/plain lf-string "SULTAN HAPROXY 443 OK\n" if is_ok
    http-request return status 403 content-type text/plain lf-string "SULTAN 403\n" if is_block

    use_backend vless_ws_backend if is_vless
    use_backend vmess_ws_backend if is_vmess
    use_backend trojan_ws_backend if is_trojan
    default_backend nginx80_backend

backend vless_ws_backend
    mode http
    option http-server-close
    server vless 127.0.0.1:$VLESS_WS_PORT check

backend vmess_ws_backend
    mode http
    option http-server-close
    server vmess 127.0.0.1:$VMESS_WS_PORT check

backend trojan_ws_backend
    mode http
    option http-server-close
    server trojan 127.0.0.1:$TROJAN_WS_PORT check

backend nginx80_backend
    mode http
    option http-server-close
    server nginx 127.0.0.1:80 check
EOF

  haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl enable haproxy >/dev/null 2>&1 && systemctl restart haproxy
  echo -e "${G}HAProxy 443 installed/configured.${N}"
  pause
}

add_user(){
  headx
  p="$1"
  mode="$2"
  d="$(domain)"
  [ "$d" = "Not Set" ] && echo "Set domain first." && pause && return
  read -rp "Username: " u
  [ -z "$u" ] && return

  if [ "$p" = "trojan" ]; then
    pass="$(openssl rand -hex 8)"
    echo "$u|$pass|trojan|$mode|$d" >> "$XDB/trojan.db"
  else
    id="$(uuidgen)"
    echo "$u|$id|$p|$mode|$d" >> "$XDB/$p.db"
  fi

  if [ "$mode" = "ws" ]; then
    xray_ws_apply_quiet
  else
    xray_tcp_apply_quiet
  fi

  headx
  if [ "$p" = "vless" ]; then
    if [ "$mode" = "ws" ]; then
      echo "vless://$id@$d:443?type=ws&encryption=none&security=tls&sni=$d&host=$d&path=%2Fvless-ws#$u"
    else
      echo "vless://$id@$d:$VLESS_TCP_PORT?type=tcp&encryption=none&security=tls&sni=$d&fp=chrome#$u"
    fi
  elif [ "$p" = "vmess" ]; then
    if [ "$mode" = "ws" ]; then
      j="{\"v\":\"2\",\"ps\":\"$u\",\"add\":\"$d\",\"port\":\"443\",\"id\":\"$id\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$d\",\"path\":\"$VMESS_WS_PATH\",\"tls\":\"tls\",\"sni\":\"$d\"}"
    else
      j="{\"v\":\"2\",\"ps\":\"$u\",\"add\":\"$d\",\"port\":\"$VMESS_TCP_PORT\",\"id\":\"$id\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"tcp\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"tls\":\"tls\",\"sni\":\"$d\"}"
    fi
    echo "vmess://$(echo -n "$j" | base64 -w0 2>/dev/null || echo -n "$j" | base64 | tr -d '\n')"
  else
    if [ "$mode" = "ws" ]; then
      echo "trojan://$pass@$d:443?type=ws&security=tls&sni=$d&host=$d&path=%2Ftrojan-ws#$u"
    else
      echo "trojan://$pass@$d:$TROJAN_TCP_PORT?security=tls&sni=$d&fp=chrome#$u"
    fi
  fi
  pause
}

xray_tcp_apply_quiet(){
  d="$(domain)"
  [ "$d" = "Not Set" ] && return
  command -v xray >/dev/null 2>&1 || return
  ensure_cert
  c="$(cert)"
  k="$(key)"
  cj="$(clients_json)"
  vl="$(echo "$cj" | jq -c .vless)"
  vm="$(echo "$cj" | jq -c .vmess)"
  tr="$(echo "$cj" | jq -c .trojan)"
  cat >"$XRAY_CONFIG" <<EOF
{"log":{"loglevel":"warning"},"dns":{"servers":["https+local://1.1.1.1/dns-query","https+local://8.8.8.8/dns-query","localhost"],"queryStrategy":"UseIP"},"inbounds":[{"tag":"vless-tcp-tls","listen":"0.0.0.0","port":$VLESS_TCP_PORT,"protocol":"vless","settings":{"clients":$vl,"decryption":"none"},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"$d","certificates":[{"certificateFile":"$c","keyFile":"$k"}],"alpn":["http/1.1"]}}},{"tag":"vmess-tcp-tls","listen":"0.0.0.0","port":$VMESS_TCP_PORT,"protocol":"vmess","settings":{"clients":$vm},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"$d","certificates":[{"certificateFile":"$c","keyFile":"$k"}],"alpn":["http/1.1"]}}},{"tag":"trojan-tcp-tls","listen":"0.0.0.0","port":$TROJAN_TCP_PORT,"protocol":"trojan","settings":{"clients":$tr},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"$d","certificates":[{"certificateFile":"$c","keyFile":"$k"}],"alpn":["http/1.1"]}}}],"outbounds":[{"tag":"direct","protocol":"freedom","settings":{"domainStrategy":"UseIP"}},{"tag":"block","protocol":"blackhole"}]}
EOF
  xray run -test -config "$XRAY_CONFIG" >/dev/null 2>&1 && systemctl restart xray >/dev/null 2>&1 || true
}

xray_ws_apply_quiet(){
  d="$(domain)"
  [ "$d" = "Not Set" ] && return
  command -v xray >/dev/null 2>&1 || return
  cj="$(clients_json)"
  vl="$(echo "$cj" | jq -c .vless)"
  vm="$(echo "$cj" | jq -c .vmess)"
  tr="$(echo "$cj" | jq -c .trojan)"
  cat >"$XRAY_CONFIG" <<EOF
{"log":{"loglevel":"warning"},"dns":{"servers":["https+local://1.1.1.1/dns-query","https+local://8.8.8.8/dns-query","localhost"],"queryStrategy":"UseIP"},"inbounds":[{"tag":"vless-ws","listen":"127.0.0.1","port":$VLESS_WS_PORT,"protocol":"vless","settings":{"clients":$vl,"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"$VLESS_WS_PATH"}}},{"tag":"vmess-ws","listen":"127.0.0.1","port":$VMESS_WS_PORT,"protocol":"vmess","settings":{"clients":$vm},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"$VMESS_WS_PATH"}}},{"tag":"trojan-ws","listen":"127.0.0.1","port":$TROJAN_WS_PORT,"protocol":"trojan","settings":{"clients":$tr},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"$TROJAN_WS_PATH"}}}],"outbounds":[{"tag":"direct","protocol":"freedom","settings":{"domainStrategy":"UseIP"}},{"tag":"block","protocol":"blackhole"}]}
EOF
  xray run -test -config "$XRAY_CONFIG" >/dev/null 2>&1 && systemctl restart xray >/dev/null 2>&1 || true
}

users(){
  headx
  echo -e "${C}VLESS${N}"
  cat "$XDB/vless.db" 2>/dev/null || true
  echo -e "\n${C}VMESS${N}"
  cat "$XDB/vmess.db" 2>/dev/null || true
  echo -e "\n${C}TROJAN${N}"
  cat "$XDB/trojan.db" 2>/dev/null || true
  pause
}

ports(){
  ufw allow 80/tcp 2>/dev/null || true
  ufw allow 443/tcp 2>/dev/null || true
  ufw allow 8443/tcp 2>/dev/null || true
  ufw allow 2083/tcp 2>/dev/null || true
  ufw allow 53/tcp 2>/dev/null || true
  ufw allow 53/udp 2>/dev/null || true
  echo -e "${G}Ports opened.${N}"
  pause
}

check(){
  headx
  echo "SERVICES:"
  echo "xray=$(svc xray) dns=$(svc dnsmasq) haproxy=$(svc haproxy) nginx=$(svc nginx)"
  echo
  echo "PORTS:"
  ss -tulpn | grep -E ':53|:80|:443|:8443|:2083|:10000|:10085|:10086' || true
  echo
  echo "DNS TEST:"
  [ "$(domain)" != "Not Set" ] && dig @127.0.0.1 "$(domain)" +short || true
  pause
}

autofix_core(){
  install_deps
  command -v xray >/dev/null 2>&1 || bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  dns_apply
  nginx80
  xray_tcp_apply
  ports
  check
}

autofix_ws(){
  install_deps
  command -v xray >/dev/null 2>&1 || bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  dns_apply
  nginx80
  xray_ws_apply
  haproxy443
  ports
  check
}

settings(){
  while true; do
    headx
    echo -e "${B}[1]${N} Install Packages"
    echo -e "${B}[2]${N} Install Xray"
    echo -e "${B}[3]${N} Set Domain"
    echo -e "${B}[4]${N} SSL"
    echo -e "${B}[5]${N} DNS Apply"
    echo -e "${B}[6]${N} Xray TCP/TLS Core"
    echo -e "${B}[7]${N} Xray WebSocket"
    echo -e "${B}[8]${N} Install/Configure Nginx 80"
    echo -e "${B}[9]${N} Install/Configure HAProxy 443"
    echo -e "${B}[10]${N} Open Ports"
    echo -e "${B}[11]${N} Check"
    echo -e "${B}[12]${N} Auto Fix Core DNS+V2Ray"
    echo -e "${B}[13]${N} Auto Fix WebSocket + HAProxy/Nginx"
    echo -e "${B}[0]${N} Back"
    read -rp "Select: " s
    case "$s" in
      1) install_deps ;;
      2) install_xray ;;
      3) set_domain ;;
      4) ssl_issue ;;
      5) dns_apply ;;
      6) xray_tcp_apply ;;
      7) xray_ws_apply ;;
      8) nginx80 ;;
      9) haproxy443 ;;
      10) ports ;;
      11) check ;;
      12) autofix_core ;;
      13) autofix_ws ;;
      0) return ;;
    esac
  done
}

menu(){
  while true; do
    headx
    echo -e "${B}[1]${N} Create VLESS TCP/TLS"
    echo -e "${B}[2]${N} Create VMESS TCP/TLS"
    echo -e "${B}[3]${N} Create TROJAN TCP/TLS"
    echo -e "${B}[4]${N} Create VLESS WebSocket"
    echo -e "${B}[5]${N} Create VMESS WebSocket"
    echo -e "${B}[6]${N} Create TROJAN WebSocket"
    echo -e "${B}[7]${N} Users"
    echo -e "${B}[8]${N} Add DNS Record"
    echo -e "${B}[9]${N} Check"
    echo -e "${B}[10]${N} Setting"
    echo -e "${B}[0]${N} Exit"
    read -rp "Select: " m
    case "$m" in
      1) add_user vless tcp ;;
      2) add_user vmess tcp ;;
      3) add_user trojan tcp ;;
      4) add_user vless ws ;;
      5) add_user vmess ws ;;
      6) add_user trojan ws ;;
      7) users ;;
      8) dns_record ;;
      9) check ;;
      10) settings ;;
      0) exit 0 ;;
    esac
  done
}

install_menu_cmd

case "$1" in
  install) echo "Installed: menu" ;;
  *) menu ;;
esac
