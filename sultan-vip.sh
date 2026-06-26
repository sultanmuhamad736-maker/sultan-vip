#!/bin/bash
set -e

BASE="/etc/sultan"
DOMAIN_FILE="$BASE/domain"
SSH_DB="$BASE/ssh_users.db"
XRAY_DIR="$BASE/xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
DNSCONF="/etc/dnsmasq.d/sultan-vip-dns.conf"
BACKUP_DIR="/root/sultan-backup"
BANDWIDTH_DIR="$BASE/bandwidth"
PIDTRACK_DIR="$BANDWIDTH_DIR/pidtrack"
SULTAN_GROUP="sultanvip"
LIMITER_SCRIPT="/usr/local/bin/sultan-vip-limiter.sh"
LIMITER_SERVICE="/etc/systemd/system/sultan-vip-limiter.service"
SSHD_SULTAN_CONFIG="/etc/ssh/sshd_config.d/sultan-vip.conf"
SSH_CONFIG_BACKUP_DIR="$BASE/ssh-backups"
BW_LOCK_DIR="/run/sultan-vip-bandwidth.lock"

VLESS_WS_PORT=10000
VMESS_WS_PORT=10085
TROJAN_WS_PORT=10086
SSH_WS_PORT=8080
UDP_PORT=7300

VLESS_WS_PATH="/vless-ws"
VMESS_WS_PATH="/vmess-ws"
TROJAN_WS_PATH="/trojan-ws"
SSH_WS_PATH="/ssh-ws"

R='\033[38;5;196m'
G='\033[38;5;46m'
Y='\033[38;5;226m'
B='\033[38;5;39m'
C='\033[38;5;51m'
P='\033[38;5;201m'
W='\033[38;5;231m'
N='\033[0m'

pause(){ echo ""; read -rp "Press Enter..." _; }
cls(){ clear 2>/dev/null || true; }

need_root(){
  if [ "$(id -u)" != "0" ]; then
    echo "Run as root."
    exit 1
  fi
}

ensure_dirs(){
  mkdir -p "$BASE" "$XRAY_DIR" "$BANDWIDTH_DIR" "$PIDTRACK_DIR" "$BACKUP_DIR" "$SSH_CONFIG_BACKUP_DIR" /etc/ssh/sshd_config.d
  touch "$SSH_DB"
  getent group "$SULTAN_GROUP" >/dev/null 2>&1 || groupadd "$SULTAN_GROUP" >/dev/null 2>&1 || true
}

install_self(){
  mkdir -p /usr/local/bin
  cp "$0" /usr/local/bin/sultan-vip 2>/dev/null || true
  cp "$0" /usr/local/bin/menu 2>/dev/null || true
  chmod +x /usr/local/bin/sultan-vip /usr/local/bin/menu 2>/dev/null || true
}

apt_update_safe(){
  local opts
  opts=(-o Acquire::Retries=3 -o Acquire::ForceIPv4=true -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 -o Acquire::http::Pipeline-Depth=0)
  DEBIAN_FRONTEND=noninteractive apt-get "${opts[@]}" update || apt update -y
}

apt_install_safe(){
  [ "$#" -eq 0 ] && return 0
  apt_update_safe
  DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Use-Pty=0 install "$@" || apt install -y "$@"
}

safe_restart_ssh(){
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || return 1
  elif command -v service >/dev/null 2>&1; then
    service sshd restart 2>/dev/null || service ssh restart 2>/dev/null || return 1
  elif [ -x /etc/init.d/sshd ]; then
    /etc/init.d/sshd restart >/dev/null 2>&1
  elif [ -x /etc/init.d/ssh ]; then
    /etc/init.d/ssh restart >/dev/null 2>&1
  else
    return 1
  fi
}

apply_ssh_config(){
  ensure_dirs
  local main_config="/etc/ssh/sshd_config"
  local backup="$SSH_CONFIG_BACKUP_DIR/sshd_config.backup.$(date +%F-%H%M%S)"
  [ -f "$main_config" ] && cp "$main_config" "$backup" 2>/dev/null || true

  cat > "$SSHD_SULTAN_CONFIG" <<EOF
PasswordAuthentication yes
PubkeyAuthentication yes
PermitRootLogin yes
UsePAM yes
TCPKeepAlive yes
ClientAliveInterval 60
ClientAliveCountMax 3
X11Forwarding no
AllowTcpForwarding yes
PermitTunnel yes
EOF

  grep -q "pam_limits.so" /etc/pam.d/sshd 2>/dev/null || echo "session required pam_limits.so" >> /etc/pam.d/sshd

  if command -v sshd >/dev/null 2>&1; then
    if ! sshd -t 2>/dev/null; then
      rm -f "$SSHD_SULTAN_CONFIG"
      [ -f "$backup" ] && cp "$backup" "$main_config" 2>/dev/null || true
      echo "ERROR: SSH config validation failed. Backup restored."
      return 1
    fi
  fi

  safe_restart_ssh || true
}

get_ip(){
  curl -4 -s --max-time 4 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}'
}

get_domain(){
  if [ -s "$DOMAIN_FILE" ]; then
    cat "$DOMAIN_FILE"
  else
    echo "Not Set"
  fi
}

active_word(){
  local s
  s="$(systemctl is-active "$1" 2>/dev/null || true)"
  if [ "$s" = "active" ]; then echo "ACTIVE"; else echo "OFFLINE"; fi
}

bbr_status(){
  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then echo "ACTIVE"; else echo "OFFLINE"; fi
}

tls_status(){
  local d
  d="$(get_domain)"
  if [ -f "/etc/letsencrypt/live/$d/fullchain.pem" ] || [ -f "/etc/sultan/$d.crt" ]; then echo "ACTIVE"; else echo "OFFLINE"; fi
}

status_color(){
  case "$1" in
    ACTIVE|READY) printf "${G}%s${N}" "$1" ;;
    OFFLINE|FAILED|ERROR) printf "${R}%s${N}" "$1" ;;
    *) printf "${Y}%s${N}" "$1" ;;
  esac
}

uptime_short(){ uptime -p 2>/dev/null | sed 's/^up //' || echo "Unknown"; }
memory_pct(){ free | awk '/Mem:/ {printf "%d", ($3/$2)*100}' 2>/dev/null || echo "0"; }
load_avg(){ awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.00"; }

server_traffic(){
  awk 'NR>2 {gsub(":","",$1); if ($1!="lo") {rx+=$2; tx+=$10}} END {printf "RX %.2f GB | TX %.2f GB | TOTAL %.2f GB", rx/1073741824, tx/1073741824, (rx+tx)/1073741824}' /proc/net/dev 2>/dev/null || echo "RX 0.00 GB | TX 0.00 GB | TOTAL 0.00 GB"
}

header(){
  cls
  local d ip
  d="$(get_domain)"
  ip="$(get_ip)"
  echo -e "${P}╔════════════════════════════════════════════════════╗${N}"
  echo -e "${P}║${W}                    SULTAN VIP                    ${P}║${N}"
  echo -e "${P}║${C}                  CROWN CORE v1.2                 ${P}║${N}"
  echo -e "${P}║${G}              SSL | WEBSOCKET | UDP CORE          ${P}║${N}"
  echo -e "${P}╚════════════════════════════════════════════════════╝${N}"
  printf " ${W}Domain       ${C}:${N} ${C}%s${N}\n" "$d"
  printf " ${W}Server IP    ${C}:${N} ${C}%s${N}\n" "$ip"
  printf " ${W}Uptime       ${C}:${N} ${G}%s${N}\n" "$(uptime_short)"
  printf " ${W}Memory       ${C}:${N} ${G}%s%%${N}        ${W}Load:${N} ${G}%s${N}\n" "$(memory_pct)" "$(load_avg)"
  printf " ${W}Traffic      ${C}:${N} ${G}%s${N}\n" "$(server_traffic)"
  echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
  printf " ${W}TLS / SSL     ${C}:${N} %s\n" "$(status_color "$(tls_status)")"
  printf " ${W}WebSocket     ${C}:${N} %s\n" "$(status_color "$(active_word sultan-ssh-ws)")"
  printf " ${W}VMESS         ${C}:${N} %s\n" "$(status_color "$(active_word xray)")"
  printf " ${W}VLESS         ${C}:${N} %s\n" "$(status_color "$(active_word xray)")"
  printf " ${W}TROJAN        ${C}:${N} %s\n" "$(status_color "$(active_word xray)")"
  printf " ${W}UDP Custom    ${C}:${N} %s\n" "$(status_color "$(active_word sultan-udpgw)")"
  printf " ${W}Nginx         ${C}:${N} %s\n" "$(status_color "$(active_word nginx)")"
  printf " ${W}HAProxy       ${C}:${N} %s\n" "$(status_color "$(active_word haproxy)")"
  printf " ${W}SSH           ${C}:${N} %s\n" "$(status_color "$(active_word ssh)")"
  printf " ${W}Fail2Ban      ${C}:${N} %s\n" "$(status_color "$(active_word fail2ban)")"
  printf " ${W}BBR           ${C}:${N} %s\n" "$(status_color "$(bbr_status)")"
  printf " ${W}Core Status   ${C}:${N} %s\n" "$(status_color READY)"
  echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
}

normalize_limit_gb(){
  local raw
  raw="$(printf "%s" "$1" | tr 'A-Z' 'a-z' | tr -d ' ')"
  raw="${raw%gb}"
  raw="${raw%g}"
  case "$raw" in ""|0|unlimited|ultimate|ultimatid|ultimated) echo 0; return ;; esac
  if echo "$raw" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then echo "$raw"; else echo ERROR; fi
}

limit_gb_to_bytes(){
  local gb
  gb="$(normalize_limit_gb "$1")"
  [ "$gb" = "ERROR" ] && echo ERROR && return
  [ "$gb" = "0" ] && echo 0 && return
  awk -v g="$gb" 'BEGIN{printf "%.0f", g*1073741824}'
}

limit_gb_display(){
  local gb
  gb="$(normalize_limit_gb "$1")"
  [ "$gb" = "ERROR" ] && echo INVALID && return
  [ "$gb" = "0" ] && echo "Unlimited" && return
  echo "$gb GB"
}

get_user_db_line(){ awk -F'|' -v u="$1" '$1==u {print; exit}' "$SSH_DB" 2>/dev/null; }
get_user_limit_gb(){ normalize_limit_gb "$(get_user_db_line "$1" | awk -F'|' '{print $2}')"; }
get_user_maxdev(){ local x; x="$(get_user_db_line "$1" | awk -F'|' '{print $3}')"; [ -z "$x" ] && x=0; echo "$x"; }

update_ssh_db_field(){
  local target_user="$1" new_limit="$2" new_max="$3" new_expire="$4" tmp="$SSH_DB.tmp"
  : > "$tmp"
  while IFS='|' read -r user limit maxdev created expire; do
    [ -z "$user" ] && continue
    if [ "$user" = "$target_user" ]; then
      [ -z "$new_limit" ] && new_limit="$limit"
      [ -z "$new_max" ] && new_max="$maxdev"
      [ -z "$new_expire" ] && new_expire="$expire"
      [ -z "$created" ] && created="$(date +%F)"
      echo "$user|$new_limit|$new_max|$created|$new_expire" >> "$tmp"
    else
      echo "$user|$limit|$maxdev|$created|$expire" >> "$tmp"
    fi
  done < "$SSH_DB"
  mv "$tmp" "$SSH_DB"
}

ssh_user_count(){ awk -F'|' 'NF && $1!="" {c++} END{print c+0}' "$SSH_DB" 2>/dev/null; }
ssh_user_by_number(){ awk -F'|' -v n="$1" 'NF && $1!="" {i++; if(i==n){print $1; exit}}' "$SSH_DB" 2>/dev/null; }

show_ssh_user_select_list(){
  echo "======================================================"
  echo "                 SELECT SSH USER"
  echo "======================================================"
  local n=1
  while IFS='|' read -r user limit maxdev created expire; do
    [ -z "$user" ] && continue
    printf "[%s] %-18s LIMIT: %-12s MAX: %-10s EXPIRE: %s\n" "$n" "$user" "$(limit_gb_display "$limit")" "$([ "$maxdev" = "0" ] && echo "Unlimited" || echo "$maxdev")" "$expire"
    n=$((n+1))
  done < "$SSH_DB"
  [ "$n" = "1" ] && echo "No users."
  echo "======================================================"
}

select_ssh_user(){
  header
  show_ssh_user_select_list
  [ "$(ssh_user_count)" = "0" ] && pause && return 1
  read -rp "Enter username or number: " target
  [ -z "$target" ] && return 1
  if echo "$target" | grep -Eq '^[0-9]+$'; then SELECTED_SSH_USER="$(ssh_user_by_number "$target")"; else SELECTED_SSH_USER="$target"; fi
  if [ -z "$SELECTED_SSH_USER" ]; then echo "Invalid selection."; pause; return 1; fi
  if ! grep -q "^$SELECTED_SSH_USER|" "$SSH_DB" && ! id "$SELECTED_SSH_USER" >/dev/null 2>&1; then echo "User not found."; pause; return 1; fi
  return 0
}

session_pids_for_user(){
  local user="$1" uid pid comm ppid login_uid f
  uid="$(id -u "$user" 2>/dev/null || echo "")"
  [ -z "$uid" ] && return 0
  {
    ps -C sshd -o pid=,user= 2>/dev/null | awk -v u="$user" '$2==u {print $1}'
    for f in /proc/[0-9]*/loginuid; do
      [ -r "$f" ] || continue
      read -r login_uid < "$f" 2>/dev/null || continue
      [ "$login_uid" = "$uid" ] || continue
      pid="${f%/loginuid}"; pid="${pid##*/}"
      [ -r "/proc/$pid/comm" ] || continue
      read -r comm < "/proc/$pid/comm" 2>/dev/null || continue
      [ "$comm" = "sshd" ] || continue
      ppid="$(awk '/^PPid:/ {print $2}' "/proc/$pid/status" 2>/dev/null)"
      [ "$ppid" = "1" ] && continue
      echo "$pid"
    done
  } | awk '!seen[$1]++'
}

online_for_user(){ session_pids_for_user "$1" | wc -l | awk '{print $1+0}'; }
usage_file_for_user(){ echo "$BANDWIDTH_DIR/$1.usage"; }
pid_file_for_user_pid(){ echo "$PIDTRACK_DIR/${1}__${2}.last"; }

read_user_usage_bytes(){
  local f v
  f="$(usage_file_for_user "$1")"
  if [ -f "$f" ]; then read -r v < "$f" || v=0; echo "${v:-0}" | awk '{print $1+0}'; else echo 0; fi
}

write_user_usage_bytes(){ printf "%s\n" "$2" > "$(usage_file_for_user "$1")"; }

lock_bandwidth(){
  local i=0
  while ! mkdir "$BW_LOCK_DIR" 2>/dev/null; do
    sleep 0.1
    i=$((i+1))
    [ "$i" -ge 50 ] && return 1
  done
  return 0
}

unlock_bandwidth(){ rmdir "$BW_LOCK_DIR" 2>/dev/null || true; }

track_user_bandwidth_now(){
  local user="$1" total delta_total pid cur rchar wchar pidfile prev d pids f fpid locked=0
  ensure_dirs
  if lock_bandwidth; then locked=1; fi
  total="$(read_user_usage_bytes "$user")"
  delta_total=0
  pids="$(session_pids_for_user "$user")"
  if [ -z "$pids" ]; then
    rm -f "$PIDTRACK_DIR/${user}__"*.last 2>/dev/null || true
    [ "$locked" = "1" ] && unlock_bandwidth
    echo "$total"
    return
  fi
  for pid in $pids; do
    cur=0
    if [ -r "/proc/$pid/io" ]; then
      rchar="$(awk '/^rchar:/ {print $2}' "/proc/$pid/io" 2>/dev/null)"
      wchar="$(awk '/^wchar:/ {print $2}' "/proc/$pid/io" 2>/dev/null)"
      rchar="${rchar:-0}"; wchar="${wchar:-0}"
      cur=$((rchar+wchar))
    fi
    pidfile="$(pid_file_for_user_pid "$user" "$pid")"
    if [ -f "$pidfile" ]; then
      read -r prev < "$pidfile" || prev=0
      prev="${prev:-0}"
      if [ "$cur" -ge "$prev" ] 2>/dev/null; then d=$((cur-prev)); else d="$cur"; fi
      delta_total=$((delta_total+d))
    fi
    printf "%s\n" "$cur" > "$pidfile"
  done
  for f in "$PIDTRACK_DIR/${user}__"*.last; do
    [ -f "$f" ] || continue
    fpid="${f##*__}"; fpid="${fpid%.last}"
    [ -d "/proc/$fpid" ] || rm -f "$f"
  done
  total=$((total+delta_total))
  write_user_usage_bytes "$user" "$total"
  [ "$locked" = "1" ] && unlock_bandwidth
  echo "$total"
}

gb_for_user(){ awk -v b="$1" 'BEGIN{printf "%.2f", b/1073741824}'; }

write_login_limits(){
  ensure_dirs
  local conf="/etc/security/limits.d/sultan-ssh-limits.conf"
  : > "$conf"
  while IFS='|' read -r user limit maxdev created expire; do
    [ -z "$user" ] && continue
    case "$maxdev" in ''|0|unlimited|Unlimited) ;; *) echo "$user hard maxlogins $maxdev" >> "$conf" ;; esac
  done < "$SSH_DB"
  apply_ssh_config >/dev/null 2>&1 || true
}

enforce_sessions_now(){
  local user limit maxdev created expire count extra pid
  while IFS='|' read -r user limit maxdev created expire; do
    [ -z "$user" ] && continue
    id "$user" >/dev/null 2>&1 || continue
    case "$maxdev" in ''|0|unlimited|Unlimited) continue ;; esac
    count="$(online_for_user "$user")"
    if [ "$count" -gt "$maxdev" ] 2>/dev/null; then
      extra=$((count-maxdev))
      session_pids_for_user "$user" | sort -n | tail -n "$extra" | while read -r pid; do [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true; done
    fi
  done < "$SSH_DB"
}

enforce_gb_limits_now(){
  local user limit maxdev created expire used quota
  while IFS='|' read -r user limit maxdev created expire; do
    [ -z "$user" ] && continue
    id "$user" >/dev/null 2>&1 || continue
    used="$(track_user_bandwidth_now "$user")"
    quota="$(limit_gb_to_bytes "$limit")"
    [ "$quota" = "ERROR" ] && quota=0
    [ "$quota" = "0" ] && continue
    if [ "$used" -ge "$quota" ] 2>/dev/null; then
      usermod -L "$user" 2>/dev/null || true
      session_pids_for_user "$user" | xargs -r kill -9 2>/dev/null || true
      pkill -u "$user" 2>/dev/null || true
    fi
  done < "$SSH_DB"
}

setup_traffic_accounting(){
  ensure_dirs
  while IFS='|' read -r user limit maxdev created expire; do
    [ -z "$user" ] && continue
    id "$user" >/dev/null 2>&1 || continue
    track_user_bandwidth_now "$user" >/dev/null 2>&1 || true
  done < "$SSH_DB"
}

rebuild_traffic_rules(){
  ensure_dirs
  rm -rf "$PIDTRACK_DIR"
  mkdir -p "$PIDTRACK_DIR"
  echo "Runtime bandwidth trackers rebuilt."
}

install_limiter_service(){
  ensure_dirs
  install_self
  cat > "$LIMITER_SCRIPT" <<'EOF'
#!/bin/bash
BASE="/etc/sultan"
SSH_DB="$BASE/ssh_users.db"
BANDWIDTH_DIR="$BASE/bandwidth"
PIDTRACK_DIR="$BANDWIDTH_DIR/pidtrack"
BW_LOCK_DIR="/run/sultan-vip-bandwidth.lock"
SCAN_INTERVAL=10
mkdir -p "$BANDWIDTH_DIR" "$PIDTRACK_DIR"

normalize_limit_gb(){
  raw="$(printf "%s" "$1" | tr 'A-Z' 'a-z' | tr -d ' ')"
  raw="${raw%gb}"; raw="${raw%g}"
  case "$raw" in ""|0|unlimited|ultimate|ultimatid|ultimated) echo 0; return ;; esac
  if echo "$raw" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then echo "$raw"; else echo ERROR; fi
}

limit_gb_to_bytes(){
  gb="$(normalize_limit_gb "$1")"
  [ "$gb" = "ERROR" ] && echo ERROR && return
  [ "$gb" = "0" ] && echo 0 && return
  awk -v g="$gb" 'BEGIN{printf "%.0f", g*1073741824}'
}

lock_bandwidth(){
  i=0
  while ! mkdir "$BW_LOCK_DIR" 2>/dev/null; do
    sleep 0.1
    i=$((i+1))
    [ "$i" -ge 50 ] && return 1
  done
  return 0
}

unlock_bandwidth(){ rmdir "$BW_LOCK_DIR" 2>/dev/null || true; }

session_pids_for_user(){
  user="$1"
  uid="$(id -u "$user" 2>/dev/null || echo "")"
  [ -z "$uid" ] && return 0
  {
    ps -C sshd -o pid=,user= 2>/dev/null | awk -v u="$user" '$2==u {print $1}'
    for f in /proc/[0-9]*/loginuid; do
      [ -r "$f" ] || continue
      read -r login_uid < "$f" 2>/dev/null || continue
      [ "$login_uid" = "$uid" ] || continue
      pid="${f%/loginuid}"; pid="${pid##*/}"
      [ -r "/proc/$pid/comm" ] || continue
      read -r comm < "/proc/$pid/comm" 2>/dev/null || continue
      [ "$comm" = "sshd" ] || continue
      ppid="$(awk '/^PPid:/ {print $2}' "/proc/$pid/status" 2>/dev/null)"
      [ "$ppid" = "1" ] && continue
      echo "$pid"
    done
  } | awk '!seen[$1]++'
}

online_for_user(){ session_pids_for_user "$1" | wc -l | awk '{print $1+0}'; }
usage_file_for_user(){ echo "$BANDWIDTH_DIR/$1.usage"; }
pid_file_for_user_pid(){ echo "$PIDTRACK_DIR/${1}__${2}.last"; }

read_user_usage_bytes(){
  f="$(usage_file_for_user "$1")"
  if [ -f "$f" ]; then read -r v < "$f" || v=0; echo "${v:-0}" | awk '{print $1+0}'; else echo 0; fi
}

write_user_usage_bytes(){ printf "%s\n" "$2" > "$(usage_file_for_user "$1")"; }

track_user_bandwidth_now(){
  user="$1"
  locked=0
  if lock_bandwidth; then locked=1; fi
  total="$(read_user_usage_bytes "$user")"
  delta_total=0
  pids="$(session_pids_for_user "$user")"
  if [ -z "$pids" ]; then
    rm -f "$PIDTRACK_DIR/${user}__"*.last 2>/dev/null || true
    [ "$locked" = "1" ] && unlock_bandwidth
    echo "$total"
    return
  fi
  for pid in $pids; do
    cur=0
    if [ -r "/proc/$pid/io" ]; then
      rchar="$(awk '/^rchar:/ {print $2}' "/proc/$pid/io" 2>/dev/null)"
      wchar="$(awk '/^wchar:/ {print $2}' "/proc/$pid/io" 2>/dev/null)"
      rchar="${rchar:-0}"; wchar="${wchar:-0}"
      cur=$((rchar+wchar))
    fi
    pidfile="$(pid_file_for_user_pid "$user" "$pid")"
    if [ -f "$pidfile" ]; then
      read -r prev < "$pidfile" || prev=0
      prev="${prev:-0}"
      if [ "$cur" -ge "$prev" ] 2>/dev/null; then d=$((cur-prev)); else d="$cur"; fi
      delta_total=$((delta_total+d))
    fi
    printf "%s\n" "$cur" > "$pidfile"
  done
  for f in "$PIDTRACK_DIR/${user}__"*.last; do
    [ -f "$f" ] || continue
    fpid="${f##*__}"; fpid="${fpid%.last}"
    [ -d "/proc/$fpid" ] || rm -f "$f"
  done
  total=$((total+delta_total))
  write_user_usage_bytes "$user" "$total"
  [ "$locked" = "1" ] && unlock_bandwidth
  echo "$total"
}

while true; do
  if [ ! -s "$SSH_DB" ]; then sleep "$SCAN_INTERVAL"; continue; fi
  while IFS='|' read -r user limit maxdev created expire; do
    [ -z "$user" ] && continue
    id "$user" >/dev/null 2>&1 || continue

    if [ -n "$expire" ] && [ "$expire" != "Unlimited" ] && [ "$expire" != "Never" ]; then
      now="$(date +%s)"
      exp_ts="$(date -d "$expire" +%s 2>/dev/null || echo 0)"
      if [ "$exp_ts" -gt 0 ] 2>/dev/null && [ "$exp_ts" -lt "$now" ] 2>/dev/null; then
        usermod -L "$user" >/dev/null 2>&1 || true
        session_pids_for_user "$user" | xargs -r kill -9 2>/dev/null || true
        pkill -u "$user" 2>/dev/null || true
        continue
      fi
    fi

    case "$maxdev" in
      ''|0|unlimited|Unlimited) ;;
      *)
        count="$(online_for_user "$user")"
        if [ "$count" -gt "$maxdev" ] 2>/dev/null; then
          extra=$((count-maxdev))
          session_pids_for_user "$user" | sort -n | tail -n "$extra" | xargs -r kill -9 2>/dev/null || true
        fi
      ;;
    esac

    used="$(track_user_bandwidth_now "$user")"
    quota="$(limit_gb_to_bytes "$limit")"
    [ "$quota" = "ERROR" ] && quota=0
    if [ "$quota" != "0" ] && [ "$used" -ge "$quota" ] 2>/dev/null; then
      usermod -L "$user" >/dev/null 2>&1 || true
      session_pids_for_user "$user" | xargs -r kill -9 2>/dev/null || true
      pkill -u "$user" 2>/dev/null || true
    fi
  done < "$SSH_DB"
  sleep "$SCAN_INTERVAL"
done
EOF

  chmod +x "$LIMITER_SCRIPT"
  cat > "$LIMITER_SERVICE" <<EOF
[Unit]
Description=SULTAN VIP Active SSH Limit And Bandwidth Enforcer
After=network.target ssh.service

[Service]
Type=simple
ExecStart=$LIMITER_SCRIPT
Restart=always
RestartSec=10
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
MemoryHigh=64M
MemoryMax=96M

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable sultan-vip-limiter >/dev/null 2>&1 || true
  systemctl restart sultan-vip-limiter 2>/dev/null || true
}

install_base(){
  header
  echo "Installing base packages..."
  apt_install_safe curl wget unzip jq uuid-runtime openssl ca-certificates certbot dnsmasq dnsutils nginx haproxy ufw psmisc iproute2 lsof iptables openssh-server python3-websockify vnstat fail2ban bc speedtest-cli
  systemctl enable ssh nginx haproxy dnsmasq vnstat fail2ban 2>/dev/null || true
  apply_ssh_config || true
  install_limiter_service
  echo "Done."
  pause
}

install_xray(){
  header
  echo "Installing Xray..."
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  systemctl enable xray 2>/dev/null || true
  echo "Done."
  pause
}

set_domain(){
  header
  read -rp "Domain: " d
  [ -z "$d" ] && return
  echo "$d" > "$DOMAIN_FILE"
  echo "Saved: $d"
  pause
}

cert_path(){
  local d
  d="$(get_domain)"
  if [ -f "/etc/letsencrypt/live/$d/fullchain.pem" ]; then echo "/etc/letsencrypt/live/$d/fullchain.pem"; else echo "/etc/sultan/$d.crt"; fi
}

key_path(){
  local d
  d="$(get_domain)"
  if [ -f "/etc/letsencrypt/live/$d/privkey.pem" ]; then echo "/etc/letsencrypt/live/$d/privkey.pem"; else echo "/etc/sultan/$d.key"; fi
}

ensure_cert(){
  local d c k
  d="$(get_domain)"
  [ "$d" = "Not Set" ] && d="$(get_ip)"
  c="$(cert_path)"; k="$(key_path)"
  if [ ! -f "$c" ] || [ ! -f "$k" ]; then
    mkdir -p /etc/sultan
    openssl req -x509 -nodes -newkey rsa:2048 -keyout "$k" -out "$c" -days 3650 -subj "/CN=$d" >/dev/null 2>&1
  fi
}

issue_ssl(){
  header
  local d
  d="$(get_domain)"
  [ "$d" = "Not Set" ] && echo "Set domain first." && pause && return
  systemctl stop nginx haproxy xray 2>/dev/null || true
  fuser -k 80/tcp 2>/dev/null || true
  certbot certonly --standalone -d "$d" --cert-name "$d" --agree-tos -m "admin@$d" --non-interactive --preferred-challenges http
  systemctl restart nginx haproxy xray 2>/dev/null || true
  pause
}

configure_dns_core(){
  local d ip
  d="$(get_domain)"; ip="$(get_ip)"
  [ "$d" = "Not Set" ] && d="local.sultan"
  cat >"$DNSCONF" <<EOF
port=53
domain-needed
bogus-priv
no-resolv
server=1.1.1.1
server=8.8.8.8
server=9.9.9.9
cache-size=10000
address=/$d/$ip
EOF
  systemctl stop systemd-resolved 2>/dev/null || true
  systemctl disable systemd-resolved 2>/dev/null || true
  rm -f /etc/resolv.conf
  printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" >/etc/resolv.conf
  fuser -k 53/tcp 2>/dev/null || true
  fuser -k 53/udp 2>/dev/null || true
  dnsmasq --test --conf-file="$DNSCONF"
  systemctl enable dnsmasq >/dev/null 2>&1 || true
  systemctl restart dnsmasq
}

configure_dns(){ header; configure_dns_core; echo "DNS ready."; pause; }

json_clients(){
  local proto="$1" db="$XRAY_DIR/$proto.db" first=1 user val mode domain extra esc_user esc_val
  printf "["
  [ -f "$db" ] || { printf "]"; return; }
  while IFS='|' read -r user val mode domain extra; do
    [ -z "$user" ] && continue
    [ -z "$val" ] && continue
    esc_user="$(printf "%s" "$user" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    esc_val="$(printf "%s" "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    [ "$first" = "1" ] || printf ","
    first=0
    case "$proto" in
      vless) printf '{"id":"%s","email":"%s"}' "$esc_val" "$esc_user" ;;
      vmess) printf '{"id":"%s","alterId":0,"email":"%s"}' "$esc_val" "$esc_user" ;;
      trojan) printf '{"password":"%s","email":"%s"}' "$esc_val" "$esc_user" ;;
    esac
  done < "$db"
  printf "]"
}

configure_xray_ws_core(){
  local d vless_clients vmess_clients trojan_clients
  d="$(get_domain)"
  [ "$d" = "Not Set" ] && return 1
  command -v xray >/dev/null 2>&1 || return 1
  mkdir -p /usr/local/etc/xray "$XRAY_DIR"
  vless_clients="$(json_clients vless)"
  vmess_clients="$(json_clients vmess)"
  trojan_clients="$(json_clients trojan)"
  cat >"$XRAY_CONFIG" <<EOF
{
  "log": {"loglevel": "warning"},
  "dns": {"servers": ["https+local://1.1.1.1/dns-query", "https+local://8.8.8.8/dns-query", "localhost"], "queryStrategy": "UseIP"},
  "inbounds": [
    {"tag": "vless-ws", "listen": "127.0.0.1", "port": $VLESS_WS_PORT, "protocol": "vless", "settings": {"clients": $vless_clients, "decryption": "none"}, "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "$VLESS_WS_PATH"}}},
    {"tag": "vmess-ws", "listen": "127.0.0.1", "port": $VMESS_WS_PORT, "protocol": "vmess", "settings": {"clients": $vmess_clients}, "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "$VMESS_WS_PATH"}}},
    {"tag": "trojan-ws", "listen": "127.0.0.1", "port": $TROJAN_WS_PORT, "protocol": "trojan", "settings": {"clients": $trojan_clients}, "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "$TROJAN_WS_PATH"}}}
  ],
  "outbounds": [{"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIP"}}, {"tag": "block", "protocol": "blackhole"}],
  "routing": {"domainStrategy": "IPIfNonMatch", "rules": [{"type": "field", "outboundTag": "block", "protocol": ["bittorrent"]}]}
}
EOF
  xray run -test -config "$XRAY_CONFIG"
  systemctl enable xray >/dev/null 2>&1 || true
  systemctl restart xray
}

configure_xray_ws(){ header; configure_xray_ws_core; echo "Xray WebSocket ready."; pause; }

configure_nginx80_core(){
  local d
  d="$(get_domain)"
  [ "$d" = "Not Set" ] && d="_"
  rm -f /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/*
  cat >/etc/nginx/conf.d/sultan-nginx-80.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $d;
    location / { return 200 "SULTAN VIP OK"; add_header Content-Type text/plain; }
    location /ok { return 200 "SULTAN 200 OK"; add_header Content-Type text/plain; }
    location /block { return 403 "SULTAN 403"; add_header Content-Type text/plain; }
}
EOF
  nginx -t
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl restart nginx
}

configure_nginx80(){ header; configure_nginx80_core; echo "Nginx 80 ready."; pause; }

configure_ssh_ws_core(){
  apply_ssh_config || true
  cat >/etc/systemd/system/sultan-ssh-ws.service <<EOF
[Unit]
Description=SULTAN SSH WebSocket Backend
After=network.target ssh.service

[Service]
ExecStart=/usr/bin/websockify 127.0.0.1:$SSH_WS_PORT 127.0.0.1:22
Restart=always
RestartSec=2
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable sultan-ssh-ws >/dev/null 2>&1 || true
  systemctl restart sultan-ssh-ws
}

configure_ssh_ws(){ header; configure_ssh_ws_core; echo "SSH WebSocket ready."; pause; }

configure_haproxy443_core(){
  local d c k hp
  d="$(get_domain)"
  [ "$d" = "Not Set" ] && d="$(get_ip)"
  ensure_cert
  c="$(cert_path)"; k="$(key_path)"; hp="/etc/haproxy/certs/$d.pem"
  mkdir -p /etc/haproxy/certs
  cat "$c" "$k" > "$hp"
  chmod 600 "$hp"
  cat >/etc/haproxy/haproxy.cfg <<EOF
global
    daemon
    maxconn 30000

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
    acl is_sshws path_beg $SSH_WS_PATH
    http-request return status 200 content-type text/plain lf-string "SULTAN HAPROXY 443 OK\n" if is_ok
    http-request return status 403 content-type text/plain lf-string "SULTAN 403\n" if is_block
    use_backend vless_ws_backend if is_vless
    use_backend vmess_ws_backend if is_vmess
    use_backend trojan_ws_backend if is_trojan
    use_backend ssh_ws_backend if is_sshws
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

backend ssh_ws_backend
    mode http
    option http-server-close
    server sshws 127.0.0.1:$SSH_WS_PORT check

backend nginx80_backend
    mode http
    option http-server-close
    server nginx 127.0.0.1:80 check
EOF
  haproxy -c -f /etc/haproxy/haproxy.cfg
  systemctl enable haproxy >/dev/null 2>&1 || true
  systemctl restart haproxy
}

configure_haproxy443(){ header; configure_haproxy443_core; echo "HAProxy 443 ready."; pause; }

configure_udp_custom(){
  header
  echo "UDP Custom install depends on badvpn-udpgw binary."
  if command -v badvpn-udpgw >/dev/null 2>&1; then
    bin="$(command -v badvpn-udpgw)"
  elif [ -x /usr/local/bin/badvpn-udpgw ]; then
    bin="/usr/local/bin/badvpn-udpgw"
  else
    echo "badvpn-udpgw not found."
    pause
    return
  fi
  cat >/etc/systemd/system/sultan-udpgw.service <<EOF
[Unit]
Description=SULTAN UDP Custom
After=network.target

[Service]
ExecStart=$bin --listen-addr 0.0.0.0:$UDP_PORT --max-clients 999
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable sultan-udpgw >/dev/null 2>&1 || true
  systemctl restart sultan-udpgw
  ufw allow "$UDP_PORT/udp" 2>/dev/null || true
  echo "UDP Custom ready."
  pause
}

open_ports_core(){
  ufw allow 22/tcp 2>/dev/null || true
  ufw allow 80/tcp 2>/dev/null || true
  ufw allow 443/tcp 2>/dev/null || true
  ufw allow 53/tcp 2>/dev/null || true
  ufw allow 53/udp 2>/dev/null || true
  ufw allow "$UDP_PORT/udp" 2>/dev/null || true
}

open_ports(){ header; open_ports_core; echo "Ports opened."; pause; }

create_ssh_user(){
  header
  ensure_dirs
  read -rp "SSH Username: " user
  [ -z "$user" ] && return
  read -rp "Password: " pass
  [ -z "$pass" ] && return
  read -rp "Days 0=Unlimited: " days
  [ -z "$days" ] && days=0
  read -rp "GB Limit 0=Unlimited: " limit_input
  [ -z "$limit_input" ] && limit_input=0
  read -rp "Max devices 0=Unlimited: " maxdev
  [ -z "$maxdev" ] && maxdev=0
  limit_gb="$(normalize_limit_gb "$limit_input")"
  if [ "$limit_gb" = "ERROR" ]; then echo "Invalid GB limit. Use 1, 1GB, 0.5, or 0."; pause; return; fi
  if ! echo "$maxdev" | grep -Eq '^[0-9]+$'; then echo "Max devices must be a number."; pause; return; fi
  if id "$user" >/dev/null 2>&1; then echo "Updating existing user."; else useradd -m -s /bin/bash "$user"; usermod -aG "$SULTAN_GROUP" "$user" 2>/dev/null || true; fi
  echo "$user:$pass" | chpasswd
  usermod -U "$user" 2>/dev/null || true
  if [ "$days" != "0" ]; then expire="$(date -d "+$days days" +%F)"; chage -E "$expire" "$user" 2>/dev/null || true; else expire="Unlimited"; chage -E -1 "$user" 2>/dev/null || true; fi
  grep -v "^$user|" "$SSH_DB" > "$SSH_DB.tmp" 2>/dev/null || true
  mv "$SSH_DB.tmp" "$SSH_DB" 2>/dev/null || true
  echo "$user|$limit_gb|$maxdev|$(date +%F)|$expire" >> "$SSH_DB"
  rm -f "$BANDWIDTH_DIR/$user.usage" "$PIDTRACK_DIR/${user}__"*.last 2>/dev/null || true
  write_user_usage_bytes "$user" 0
  write_login_limits
  install_limiter_service
  enforce_sessions_now
  header
  echo "SSH USER CREATED"
  echo "Username    : $user"
  echo "Password    : $pass"
  echo "GB Limit    : $(limit_gb_display "$limit_gb")"
  echo "Max Devices : $([ "$maxdev" = "0" ] && echo "Unlimited" || echo "$maxdev")"
  echo "Expire      : $expire"
  echo "SSH WS Path : $SSH_WS_PATH"
  echo "Limiter     : ACTIVE"
  pause
}

change_ssh_password(){ select_ssh_user || return; user="$SELECTED_SSH_USER"; read -rp "New password for $user: " pass; [ -z "$pass" ] && return; echo "$user:$pass" | chpasswd; echo "Password changed: $user"; pause; }
change_ssh_gb_limit(){ select_ssh_user || return; user="$SELECTED_SSH_USER"; read -rp "New GB limit for $user, 0=Unlimited: " limit_input; [ -z "$limit_input" ] && return; limit_gb="$(normalize_limit_gb "$limit_input")"; [ "$limit_gb" = "ERROR" ] && echo "Invalid GB limit." && pause && return; update_ssh_db_field "$user" "$limit_gb" "" ""; usermod -U "$user" 2>/dev/null || true; install_limiter_service; enforce_gb_limits_now; echo "GB limit updated: $user -> $(limit_gb_display "$limit_gb")"; pause; }
change_ssh_max_devices(){ select_ssh_user || return; user="$SELECTED_SSH_USER"; read -rp "New max devices for $user, 0=Unlimited: " maxdev; [ -z "$maxdev" ] && return; echo "$maxdev" | grep -Eq '^[0-9]+$' || { echo "Max devices must be a number."; pause; return; }; update_ssh_db_field "$user" "" "$maxdev" ""; write_login_limits; install_limiter_service; enforce_sessions_now; echo "Max devices updated: $user -> $([ "$maxdev" = "0" ] && echo "Unlimited" || echo "$maxdev")"; pause; }
change_ssh_expire_days(){ select_ssh_user || return; user="$SELECTED_SSH_USER"; read -rp "New days for $user, 0=Unlimited: " days; [ -z "$days" ] && return; echo "$days" | grep -Eq '^[0-9]+$' || { echo "Days must be a number."; pause; return; }; if [ "$days" = "0" ]; then expire="Unlimited"; chage -E -1 "$user" 2>/dev/null || true; else expire="$(date -d "+$days days" +%F)"; chage -E "$expire" "$user" 2>/dev/null || true; fi; update_ssh_db_field "$user" "" "" "$expire"; install_limiter_service; echo "Expire updated: $user -> $expire"; pause; }
lock_ssh_user(){ select_ssh_user || return; user="$SELECTED_SSH_USER"; usermod -L "$user"; session_pids_for_user "$user" | xargs -r kill -9 2>/dev/null || true; pkill -u "$user" 2>/dev/null || true; echo "Locked: $user"; pause; }
unlock_ssh_user(){ select_ssh_user || return; user="$SELECTED_SSH_USER"; usermod -U "$user" 2>/dev/null || true; echo "Unlocked: $user"; pause; }
reset_user_traffic(){ select_ssh_user || return; user="$SELECTED_SSH_USER"; rm -f "$PIDTRACK_DIR/${user}__"*.last 2>/dev/null || true; write_user_usage_bytes "$user" 0; usermod -U "$user" 2>/dev/null || true; echo "Traffic reset: $user"; pause; }

delete_ssh_user(){
  select_ssh_user || return
  user="$SELECTED_SSH_USER"
  echo "Selected: $user"
  read -rp "Type DELETE to confirm: " confirm
  [ "$confirm" != "DELETE" ] && echo "Cancelled." && pause && return
  session_pids_for_user "$user" | xargs -r kill -9 2>/dev/null || true
  pkill -u "$user" 2>/dev/null || true
  userdel -r "$user" 2>/dev/null || userdel "$user" 2>/dev/null || true
  grep -v "^$user|" "$SSH_DB" > "$SSH_DB.tmp" 2>/dev/null || true
  mv "$SSH_DB.tmp" "$SSH_DB" 2>/dev/null || true
  rm -f "$BANDWIDTH_DIR/$user.usage" "$PIDTRACK_DIR/${user}__"*.last 2>/dev/null || true
  write_login_limits
  echo "Deleted: $user"
  pause
}

ssh_live_monitor(){
  setup_traffic_accounting
  enforce_sessions_now
  enforce_gb_limits_now
  cls
  echo "======================================================"
  echo "              SSH USERS LIVE MONITOR"
  echo "======================================================"
  printf "%-18s %-18s %-15s %s\n" "SSH USER" "ONLINE" "USED" "LIMIT"
  echo "======================================================"
  if [ ! -s "$SSH_DB" ]; then
    echo "No SSH users."
  else
    while IFS='|' read -r user limit maxdev created expire; do
      [ -z "$user" ] && continue
      id "$user" >/dev/null 2>&1 || continue
      used_bytes="$(track_user_bandwidth_now "$user")"
      printf "%-18s ● %-15s %-15s %s\n" "$user" "$(online_for_user "$user")" "$(gb_for_user "$used_bytes") GB" "$(limit_gb_display "$limit")"
    done < "$SSH_DB"
  fi
  echo "======================================================"
  echo "USED = live SSH usage, LIMIT = display only"
  pause
}

list_ssh_users(){
  header
  echo "SSH USERS"
  echo "======================================================"
  local n=1
  while IFS='|' read -r user limit maxdev created expire; do
    [ -z "$user" ] && continue
    printf "[%s] %s | Limit: %s | Max: %s | Expire: %s\n" "$n" "$user" "$(limit_gb_display "$limit")" "$([ "$maxdev" = "0" ] && echo "Unlimited" || echo "$maxdev")" "$expire"
    n=$((n+1))
  done < "$SSH_DB"
  [ "$n" = "1" ] && echo "No users."
  pause
}

create_v2ray_user(){
  local proto="$1" d user idv pass j
  header
  d="$(get_domain)"
  [ "$d" = "Not Set" ] && echo "Set domain first." && pause && return
  read -rp "Username: " user
  [ -z "$user" ] && return
  mkdir -p "$XRAY_DIR"
  case "$proto" in
    vless)
      idv="$(uuidgen)"
      echo "$user|$idv|ws|$d|$VLESS_WS_PATH" >> "$XRAY_DIR/vless.db"
      configure_xray_ws_core
      echo "vless://$idv@$d:443?type=ws&encryption=none&security=tls&sni=$d&host=$d&path=%2Fvless-ws#$user"
    ;;
    vmess)
      idv="$(uuidgen)"
      echo "$user|$idv|ws|$d|$VMESS_WS_PATH" >> "$XRAY_DIR/vmess.db"
      configure_xray_ws_core
      j="{\"v\":\"2\",\"ps\":\"$user\",\"add\":\"$d\",\"port\":\"443\",\"id\":\"$idv\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$d\",\"path\":\"$VMESS_WS_PATH\",\"tls\":\"tls\",\"sni\":\"$d\"}"
      echo "vmess://$(echo -n "$j" | base64 -w0 2>/dev/null || echo -n "$j" | base64 | tr -d '\n')"
    ;;
    trojan)
      pass="$(openssl rand -hex 8)"
      echo "$user|$pass|ws|$d|$TROJAN_WS_PATH" >> "$XRAY_DIR/trojan.db"
      configure_xray_ws_core
      echo "trojan://$pass@$d:443?type=ws&security=tls&sni=$d&host=$d&path=%2Ftrojan-ws#$user"
    ;;
  esac
  pause
}

restart_all(){ systemctl restart ssh sshd 2>/dev/null || true; systemctl restart sultan-ssh-ws xray nginx haproxy dnsmasq fail2ban sultan-udpgw sultan-vip-limiter 2>/dev/null || true; }
stop_all(){ systemctl stop sultan-ssh-ws xray nginx haproxy dnsmasq sultan-udpgw 2>/dev/null || true; }
install_fail2ban(){ apt_install_safe fail2ban; systemctl enable --now fail2ban; }
enable_bbr(){ modprobe tcp_bbr 2>/dev/null || true; grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf; sysctl -p >/dev/null 2>&1 || true; }

backup_script(){ mkdir -p "$BACKUP_DIR"; tar -czf "$BACKUP_DIR/sultan-backup-$(date +%F-%H%M%S).tar.gz" "$BASE" /usr/local/etc/xray /etc/haproxy /etc/nginx 2>/dev/null || true; echo "Backup saved in $BACKUP_DIR"; pause; }
restore_script(){ header; ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true; read -rp "Backup file path: " f; [ -f "$f" ] || { echo "File not found."; pause; return; }; tar -xzf "$f" -C / 2>/dev/null || true; restart_all; echo "Restore done."; pause; }
show_logs(){ header; echo "[1] Xray"; echo "[2] HAProxy"; echo "[3] Nginx"; echo "[4] SSH WebSocket"; echo "[5] Limiter"; read -rp "Select: " x; case "$x" in 1) journalctl -u xray -n 80 --no-pager ;; 2) journalctl -u haproxy -n 80 --no-pager ;; 3) journalctl -u nginx -n 80 --no-pager ;; 4) journalctl -u sultan-ssh-ws -n 80 --no-pager ;; 5) journalctl -u sultan-vip-limiter -n 80 --no-pager ;; esac; pause; }
clean_old_configs(){ rm -f /etc/nginx/sites-enabled/* /etc/nginx/conf.d/default.conf 2>/dev/null || true; echo "Old configs cleaned."; pause; }
repair_ssh(){ apt_install_safe openssh-server python3-websockify; apply_ssh_config || true; configure_ssh_ws_core; write_login_limits; install_limiter_service; echo "SSH repaired."; pause; }
repair_firewall(){ open_ports_core; echo "Firewall repaired."; pause; }

system_info(){
  header
  uname -a
  echo ""
  free -h
  echo ""
  df -h /
  echo ""
  ss -tulpn | grep -E ':22|:53|:80|:443|:7300|:8080|:10000|:10085|:10086' || true
  pause
}

auto_fix_all(){
  header
  apt_install_safe curl wget unzip jq uuid-runtime openssl ca-certificates certbot dnsmasq dnsutils nginx haproxy ufw psmisc iproute2 lsof iptables openssh-server python3-websockify vnstat fail2ban bc speedtest-cli
  command -v xray >/dev/null 2>&1 || bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  configure_dns_core
  apply_ssh_config || true
  configure_ssh_ws_core
  configure_xray_ws_core || true
  configure_nginx80_core
  configure_haproxy443_core
  open_ports_core
  setup_traffic_accounting
  write_login_limits
  install_limiter_service
  systemctl enable vnstat fail2ban 2>/dev/null || true
  systemctl restart vnstat fail2ban 2>/dev/null || true
  echo "Auto Fix ALL completed."
  pause
}

check_all(){
  header
  echo "SERVICES:"
  echo "ssh=$(systemctl is-active ssh 2>/dev/null || echo off)"
  echo "xray=$(systemctl is-active xray 2>/dev/null || echo off)"
  echo "dnsmasq=$(systemctl is-active dnsmasq 2>/dev/null || echo off)"
  echo "nginx=$(systemctl is-active nginx 2>/dev/null || echo off)"
  echo "haproxy=$(systemctl is-active haproxy 2>/dev/null || echo off)"
  echo "ssh-ws=$(systemctl is-active sultan-ssh-ws 2>/dev/null || echo off)"
  echo "limiter=$(systemctl is-active sultan-vip-limiter 2>/dev/null || echo off)"
  echo "udpgw=$(systemctl is-active sultan-udpgw 2>/dev/null || echo off)"
  echo ""
  echo "PORTS:"
  ss -tulpn | grep -E ':22|:53|:80|:443|:7300|:8080|:10000|:10085|:10086' || true
  echo ""
  echo "DNS TEST:"
  d="$(get_domain)"
  [ "$d" != "Not Set" ] && dig @127.0.0.1 "$d" +short 2>/dev/null || true
  pause
}

ssh_menu(){
  while true; do
    header
    echo -e " ${B}[1]${N}  ${G}CREATE SSH USER${N}"
    echo -e " ${B}[2]${N}  ${G}LIST SSH USERS${N}"
    echo -e " ${B}[3]${N}  ${G}TRAFFIC${N}"
    echo -e " ${B}[4]${N}  ${G}ENFORCE LIMITS NOW${N}"
    echo -e " ${B}[5]${N}  ${G}CHANGE SSH PASSWORD${N}"
    echo -e " ${B}[6]${N}  ${G}CHANGE GB LIMIT${N}"
    echo -e " ${B}[7]${N}  ${G}CHANGE MAX DEVICES${N}"
    echo -e " ${B}[8]${N}  ${G}CHANGE EXPIRE DAYS${N}"
    echo -e " ${B}[9]${N}  ${G}RESET USER TRAFFIC${N}"
    echo -e " ${B}[10]${N} ${G}LOCK SSH USER${N}"
    echo -e " ${B}[11]${N} ${G}UNLOCK SSH USER${N}"
    echo -e " ${B}[12]${N} ${G}REBUILD TRAFFIC RUNTIME${N}"
    echo -e " ${R}[13]${N} ${R}DELETE SSH USER${N}"
    echo -e " ${Y}[0]${N}  ${Y}BACK${N}"
    read -rp "Select: " s
    case "$s" in
      1) create_ssh_user ;;
      2) list_ssh_users ;;
      3) ssh_live_monitor ;;
      4) setup_traffic_accounting; write_login_limits; install_limiter_service; enforce_sessions_now; enforce_gb_limits_now; echo "Done."; pause ;;
      5) change_ssh_password ;;
      6) change_ssh_gb_limit ;;
      7) change_ssh_max_devices ;;
      8) change_ssh_expire_days ;;
      9) reset_user_traffic ;;
      10) lock_ssh_user ;;
      11) unlock_ssh_user ;;
      12) rebuild_traffic_rules; install_limiter_service; echo "Runtime rebuilt."; pause ;;
      13) delete_ssh_user ;;
      0) return ;;
    esac
  done
}

domain_menu(){ while true; do header; echo -e " ${B}[1]${N} ${G}SET DOMAIN${N}"; echo -e " ${B}[2]${N} ${G}SHOW DOMAIN${N}"; echo -e " ${Y}[0]${N} ${Y}BACK${N}"; read -rp "Select: " s; case "$s" in 1) set_domain ;; 2) echo "$(get_domain)"; pause ;; 0) return ;; esac; done; }
ssl_menu(){ while true; do header; echo -e " ${B}[1]${N} ${G}ISSUE SSL${N}"; echo -e " ${B}[2]${N} ${G}SHOW SSL STATUS${N}"; echo -e " ${Y}[0]${N} ${Y}BACK${N}"; read -rp "Select: " s; case "$s" in 1) issue_ssl ;; 2) echo "$(tls_status)"; pause ;; 0) return ;; esac; done; }
xray_menu(){ while true; do header; echo -e " ${B}[1]${N} ${G}INSTALL XRAY${N}"; echo -e " ${B}[2]${N} ${G}CONFIGURE XRAY WEBSOCKET${N}"; echo -e " ${B}[3]${N} ${G}RESTART XRAY${N}"; echo -e " ${Y}[0]${N} ${Y}BACK${N}"; read -rp "Select: " s; case "$s" in 1) install_xray ;; 2) configure_xray_ws ;; 3) systemctl restart xray; pause ;; 0) return ;; esac; done; }

setting_menu(){
  while true; do
    header
    echo -e " ${B}[1]${N}  ${G}INSTALL BASE PACKAGES${N}"
    echo -e " ${B}[2]${N}  ${G}INSTALL XRAY${N}"
    echo -e " ${B}[3]${N}  ${G}SET DOMAIN${N}"
    echo -e " ${B}[4]${N}  ${G}ISSUE SSL${N}"
    echo -e " ${B}[5]${N}  ${G}CONFIGURE DNS${N}"
    echo -e " ${B}[6]${N}  ${G}CONFIGURE SSH WEBSOCKET${N}"
    echo -e " ${B}[7]${N}  ${G}CONFIGURE XRAY WEBSOCKET${N}"
    echo -e " ${B}[8]${N}  ${G}CONFIGURE NGINX 80${N}"
    echo -e " ${B}[9]${N}  ${G}CONFIGURE HAPROXY 443${N}"
    echo -e " ${B}[10]${N} ${G}CONFIGURE UDP CUSTOM${N}"
    echo -e " ${B}[11]${N} ${G}INSTALL FAIL2BAN${N}"
    echo -e " ${B}[12]${N} ${G}ENABLE BBR${N}"
    echo -e " ${B}[13]${N} ${G}OPEN PORTS${N}"
    echo -e " ${B}[14]${N} ${G}RESTART ALL SERVICES${N}"
    echo -e " ${B}[15]${N} ${G}STOP ALL SERVICES${N}"
    echo -e " ${B}[16]${N} ${G}CHECK ALL SERVICES${N}"
    echo -e " ${B}[17]${N} ${G}AUTO FIX ALL${N}"
    echo -e " ${B}[18]${N} ${G}SSH TRAFFIC MONITOR${N}"
    echo -e " ${B}[19]${N} ${G}ENFORCE SSH LIMITS${N}"
    echo -e " ${B}[20]${N} ${G}BACKUP SCRIPT DATA${N}"
    echo -e " ${B}[21]${N} ${G}RESTORE SCRIPT DATA${N}"
    echo -e " ${B}[22]${N} ${G}UPDATE SCRIPT${N}"
    echo -e " ${R}[23]${N} ${R}REMOVE SCRIPT${N}"
    echo -e " ${B}[24]${N} ${G}SHOW SERVICE LOGS${N}"
    echo -e " ${B}[25]${N} ${G}CLEAN OLD CONFIGS${N}"
    echo -e " ${B}[26]${N} ${G}REPAIR SSH${N}"
    echo -e " ${B}[27]${N} ${G}REPAIR FIREWALL${N}"
    echo -e " ${B}[28]${N} ${G}REBUILD TRAFFIC RUNTIME${N}"
    echo -e " ${B}[29]${N} ${G}SYSTEM INFO${N}"
    echo -e " ${Y}[0]${N}  ${Y}BACK${N}"
    read -rp "Select: " s
    case "$s" in
      1) install_base ;;
      2) install_xray ;;
      3) set_domain ;;
      4) issue_ssl ;;
      5) configure_dns ;;
      6) configure_ssh_ws ;;
      7) configure_xray_ws ;;
      8) configure_nginx80 ;;
      9) configure_haproxy443 ;;
      10) configure_udp_custom ;;
      11) install_fail2ban; pause ;;
      12) enable_bbr; pause ;;
      13) open_ports ;;
      14) restart_all; echo "All services restarted."; pause ;;
      15) stop_all; echo "All services stopped."; pause ;;
      16) check_all ;;
      17) auto_fix_all ;;
      18) ssh_live_monitor ;;
      19) setup_traffic_accounting; write_login_limits; install_limiter_service; enforce_sessions_now; enforce_gb_limits_now; echo "Done."; pause ;;
      20) backup_script ;;
      21) restore_script ;;
      22) install_self; echo "Script command refreshed."; pause ;;
      23) read -rp "Type REMOVE to confirm: " c; [ "$c" = "REMOVE" ] && rm -f /usr/local/bin/menu /usr/local/bin/sultan-vip && echo "Removed."; pause ;;
      24) show_logs ;;
      25) clean_old_configs ;;
      26) repair_ssh ;;
      27) repair_firewall ;;
      28) rebuild_traffic_rules; install_limiter_service; echo "Runtime rebuilt."; pause ;;
      29) system_info ;;
      0) return ;;
    esac
  done
}

about_script(){ header; echo "SULTAN VIP CROWN CORE v1.2"; echo "SSH, WebSocket, V2Ray, Nginx, HAProxy, DNS, UDP Core"; pause; }

main_menu(){
  while true; do
    header
    echo -e " ${B}[1]${N}  ${G}SSH MENU${N}              ${B}[11]${N} ${G}REBOOT VPS${N}"
    echo -e " ${B}[2]${N}  ${G}VMESS MENU${N}            ${B}[12]${N} ${G}ABOUT SCRIPT${N}"
    echo -e " ${B}[3]${N}  ${G}VLESS MENU${N}            ${B}[13]${N} ${G}VPS INFO${N}"
    echo -e " ${B}[4]${N}  ${G}TROJAN MENU${N}           ${B}[14]${N} ${G}ONLINE USERS${N}"
    echo -e " ${B}[5]${N}  ${G}SSR MENU${N}              ${B}[15]${N} ${G}SPEEDTEST${N}"
    echo -e " ${B}[6]${N}  ${G}UDP CUSTOM${N}            ${B}[16]${N} ${G}DOMAIN MENU${N}"
    echo -e " ${B}[7]${N}  ${G}BOT TELEGRAM${N}          ${B}[17]${N} ${G}SSL MENU${N}"
    echo -e " ${B}[8]${N}  ${G}UPDATE SCRIPT${N}         ${B}[18]${N} ${G}XRAY MENU${N}"
    echo -e " ${B}[9]${N}  ${G}BACKUP RESTORE${N}        ${B}[19]${N} ${G}FAIL2BAN MENU${N}"
    echo -e " ${B}[10]${N} ${G}SETTING${N}               ${B}[20]${N} ${G}BBR MENU${N}"
    echo -e " ${Y}[50]${N} ${Y}TROUBLESHOOTING${N}       ${R}[99]${N} ${R}REMOVE SCRIPT${N}"
    echo -e " ${Y}[X]${N}  ${Y}EXIT${N}"
    read -rp "Select: " m
    case "$m" in
      1) ssh_menu ;;
      2) create_v2ray_user vmess ;;
      3) create_v2ray_user vless ;;
      4) create_v2ray_user trojan ;;
      5) echo "SSR menu is not installed."; pause ;;
      6) configure_udp_custom ;;
      7) echo "Telegram bot is not installed."; pause ;;
      8) install_self; echo "Script refreshed."; pause ;;
      9) backup_script ;;
      10) setting_menu ;;
      11) reboot ;;
      12) about_script ;;
      13) system_info ;;
      14) ssh_live_monitor ;;
      15) speedtest-cli 2>/dev/null || { apt_install_safe speedtest-cli && speedtest-cli; }; pause ;;
      16) domain_menu ;;
      17) ssl_menu ;;
      18) xray_menu ;;
      19) install_fail2ban; pause ;;
      20) enable_bbr; pause ;;
      50) check_all ;;
      99) read -rp "Type REMOVE to confirm: " c; [ "$c" = "REMOVE" ] && rm -f /usr/local/bin/menu /usr/local/bin/sultan-vip && echo "Removed."; pause ;;
      x|X) exit 0 ;;
      0) exit 0 ;;
    esac
  done
}

need_root
ensure_dirs
install_self

case "$1" in
  monitor) ssh_live_monitor ;;
  fix) auto_fix_all ;;
  menu|"") main_menu ;;
  *) main_menu ;;
esac
