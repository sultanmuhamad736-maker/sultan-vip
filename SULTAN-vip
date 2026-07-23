#!/bin/bash
# ==========================================================
# SULTAN VIP FULL PURPLE MENU INSTALL
# Full verified installer + full panel + SSL/TLS/SNI/WS/V2Ray WebSocket
# Build: v33-VMESS-LINK V33-BASE + REAL-VMESS-LINK-MENU
# Integrated real SSH login limit + per-user GB quota
# 0 Max Login = Unlimited
# 0 GB Limit   = Unlimited
# ==========================================================

# Never run this installer with 'source' or '.'. A sourced script can terminate
# the parent SSH shell when it reaches an exit statement.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "Do not source this installer. Run it with: bash ${BASH_SOURCE[0]}"
  return 1
fi

set -Ee
set -o pipefail
trap 'echo "Installer error near line $LINENO. Check the command above."' ERR
trap 'echo; echo "Installation interrupted safely. Your SSH shell is still active."; exit 130' INT
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
LIMIT_DIR="$BASE/limits"

mkdir -p "$BASE" "$XDB" "$LIMIT_DIR"
touch "$DB" "$LIMIT_DIR/usage.db" "$LIMIT_DIR/blocked.db" "$LIMIT_DIR/quota-locked.db" "$LIMIT_DIR/devices.db" "$LIMIT_DIR/device_sessions.log" "$LIMIT_DIR/device_usage.db"
chmod 700 "$BASE" "$XDB" "$LIMIT_DIR"
chmod 600 "$DB" "$LIMIT_DIR/usage.db" "$LIMIT_DIR/blocked.db" "$LIMIT_DIR/quota-locked.db" "$LIMIT_DIR/devices.db" "$LIMIT_DIR/device_sessions.log" "$LIMIT_DIR/device_usage.db"

# Store unlimited quota/login limits as the literal numeric value 0.
# This also repairs legacy Unlimited values, whitespace and CRLF endings.
# Passwords remain in users.db for compatibility with the legacy panel behavior.
normalize_limit_fields_zero(){
  local FILE="$1" EXP_FIELD="$2" QUOTA_FIELD="$3" LOGIN_FIELD="$4" TMP
  [ -f "$FILE" ] || return 0
  TMP="$(mktemp "${FILE}.normalize.XXXXXX")" || return 1
  awk -F'|' -v ef="$EXP_FIELD" -v qf="$QUOTA_FIELD" -v lf="$LOGIN_FIELD" '
    BEGIN{OFS="|"}
    function clean(v){
      gsub(/\r/, "", v)
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]]+$/, "", v)
      return v
    }
    function is_unlimited(v, lower){
      lower=tolower(v)
      return (v=="" || v ~ /^0+$/ || lower=="unlimited")
    }
    {
      if(NF>=ef){$ef=clean($ef); if(is_unlimited($ef)) $ef="0"}
      if(NF>=qf){$qf=clean($qf); if(is_unlimited($qf)) $qf="0"}
      if(NF>=lf){$lf=clean($lf); if(is_unlimited($lf)) $lf="0"}
      print
    }
  ' "$FILE" > "$TMP" || { rm -f "$TMP"; return 1; }
  chmod 600 "$TMP"
  mv -f "$TMP" "$FILE"
}

normalize_limit_fields_zero "$DB" 3 4 5
for LEGACY_XRAY_DB in "$XDB/vmess-ws.db" "$XDB/vless-ws.db" "$XDB/trojan-ws.db"; do
  [ -f "$LEGACY_XRAY_DB" ] && normalize_limit_fields_zero "$LEGACY_XRAY_DB" 7 8 9
done

echo "==========================================="
echo "        SULTAN VIP FULL PURPLE MENU INSTALL"
echo "==========================================="
echo "[1/6] Installing required packages..."

if [ ! -r /etc/os-release ]; then
  echo "Unsupported system: /etc/os-release is missing."
  exit 1
fi
. /etc/os-release
case "${ID:-}" in
  debian|ubuntu) ;;
  *)
    echo "Unsupported system: ${PRETTY_NAME:-unknown}. Use Debian or Ubuntu."
    exit 1
    ;;
esac

apt_retry(){
  local TRY
  for TRY in 1 2 3; do
    if apt-get "$@"; then
      return 0
    fi
    echo "APT attempt $TRY failed; retrying..."
    sleep $((TRY * 3))
  done
  return 1
}

apt_retry update
apt_retry install -y curl wget nginx haproxy openssh-server python3 \
  certbot python3-certbot-nginx ufw socat lsb-release bc jq uuid-runtime vnstat \
  fail2ban openssl speedtest-cli dnsutils iproute2 tar gzip ca-certificates psmisc \
  nftables procps gawk util-linux coreutils grep sed findutils passwd login

for CMD in curl nginx haproxy sshd python3 certbot ufw jq nft flock openssl systemctl; do
  command -v "$CMD" >/dev/null 2>&1 || {
    echo "Required command was not installed: $CMD"
    exit 1
  }
done

# Ask once before the final installation stage about existing normal users.
# y deletes them; n keeps them exactly as system accounts and imports them into
# the SULTAN SSH users database. Xray users and all other installer features are untouched.
handle_existing_users_before_final(){
  local USERS_FILE ANSWER U OLD_LINE OLD_PASS OLD_EXP OLD_QUOTA OLD_LOGIN
  local SHADOW_EXPIRE EXP TMP TMP2 FILE IMPORTED=0 DELETED=0

  USERS_FILE="$(mktemp "$BASE/.existing-users.XXXXXX")" || return 1
  awk -F: '$3>=1000 && $1!="nobody"{print $1}' /etc/passwd | sort -u > "$USERS_FILE"

  echo "==========================================="
  echo "[Existing SSH users check]"
  echo "Command: awk -F: '\''$3>=1000 && $1!=\"nobody\"{print $1}'\'' /etc/passwd"
  echo "-------------------------------------------"
  awk -F: '$3>=1000 && $1!="nobody"{print $1}' /etc/passwd
  [ -s "$USERS_FILE" ] || echo "(no users found)"
  echo "==========================================="

  while true; do
    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
      printf 'Are you sure you want to delete these users? (y/n): ' > /dev/tty
      IFS= read -r ANSWER < /dev/tty || ANSWER=""
    else
      printf 'Are you sure you want to delete these users? (y/n): '
      IFS= read -r ANSWER || ANSWER=""
    fi

    case "$ANSWER" in
      y|Y)
        for U in $(awk -F: '$3>=1000 && $1!="nobody"{print $1}' /etc/passwd); do
          userdel -r "$U" 2>/dev/null || true
          rm -rf "/run/sultan-login-slots/$U" 2>/dev/null || true
          DELETED=$((DELETED + 1))
        done

        # Remove only deleted SSH names from SULTAN records, allowing those
        # usernames to be created again later without stale database entries.
        for FILE in "$DB" \
                    "$LIMIT_DIR/usage.db" \
                    "$LIMIT_DIR/blocked.db" \
                    "$LIMIT_DIR/quota-locked.db" \
                    "$LIMIT_DIR/devices.db" \
                    "$LIMIT_DIR/device_sessions.log" \
                    "$LIMIT_DIR/device_usage.db"; do
          [ -f "$FILE" ] || continue
          TMP="$(mktemp "${FILE}.cleanup.XXXXXX")" || { rm -f "$USERS_FILE"; return 1; }
          awk -F'|' 'NR==FNR{drop[$1]=1;next} !($1 in drop)' "$USERS_FILE" "$FILE" > "$TMP" || {
            rm -f "$TMP" "$USERS_FILE"
            return 1
          }
          chmod 600 "$TMP"
          mv -f "$TMP" "$FILE"
        done

        rm -f "$USERS_FILE"
        echo "Deleted users: $DELETED"
        return 0
        ;;

      n|N)
        # Keep each Linux account, password hash, UID, home, shell and expiry as-is.
        # Import it into users.db so it appears in the SULTAN SSH user list.
        TMP="$(mktemp "$BASE/.users-import.XXXXXX")" || { rm -f "$USERS_FILE"; return 1; }
        cp -a "$DB" "$TMP" 2>/dev/null || : > "$TMP"

        while IFS= read -r U; do
          [ -n "$U" ] || continue
          id "$U" >/dev/null 2>&1 || continue

          OLD_LINE="$(awk -F'|' -v u="$U" '$1==u{print;exit}' "$TMP" 2>/dev/null || true)"
          OLD_PASS="$(printf '%s\n' "$OLD_LINE" | awk -F'|' '{print $2}')"
          OLD_EXP="$(printf '%s\n' "$OLD_LINE" | awk -F'|' '{print $3}')"
          OLD_QUOTA="$(printf '%s\n' "$OLD_LINE" | awk -F'|' '{print $4}')"
          OLD_LOGIN="$(printf '%s\n' "$OLD_LINE" | awk -F'|' '{print $5}')"

          case "$OLD_EXP" in
            ""|0|Unlimited|unlimited|UNLIMITED) OLD_EXP="0" ;;
          esac
          case "$OLD_QUOTA" in
            ""|0|Unlimited|unlimited|UNLIMITED) OLD_QUOTA="0" ;;
          esac
          case "$OLD_LOGIN" in
            ""|0|Unlimited|unlimited|UNLIMITED) OLD_LOGIN="0" ;;
          esac

          # Preserve a stored SULTAN expiry when present. Otherwise import the
          # system account expiry; no expiry is stored as the literal value 0.
          if [ -n "$OLD_LINE" ]; then
            EXP="$OLD_EXP"
          else
            SHADOW_EXPIRE="$(awk -F: -v u="$U" '$1==u{print $8;exit}' /etc/shadow 2>/dev/null || true)"
            if [[ "$SHADOW_EXPIRE" =~ ^[0-9]+$ ]] && [ "$SHADOW_EXPIRE" -gt 0 ]; then
              EXP="$(date -u -d "1970-01-01 +${SHADOW_EXPIRE} days" +%Y-%m-%d 2>/dev/null || echo 0)"
            else
              EXP="0"
            fi
          fi

          TMP2="$(mktemp "$BASE/.users-one.XXXXXX")" || {
            rm -f "$TMP" "$USERS_FILE"
            return 1
          }
          awk -F'|' -v u="$U" '$1!=u' "$TMP" > "$TMP2" 2>/dev/null || true
          printf '%s|%s|%s|%s|%s\n' "$U" "$OLD_PASS" "$EXP" "$OLD_QUOTA" "$OLD_LOGIN" >> "$TMP2"
          chmod 600 "$TMP2"
          mv -f "$TMP2" "$TMP"
          IMPORTED=$((IMPORTED + 1))
        done < "$USERS_FILE"

        chmod 600 "$TMP"
        mv -f "$TMP" "$DB"
        rm -f "$USERS_FILE"
        /usr/local/sbin/sultan-quota-sync >/dev/null 2>&1 || true
        echo "Imported existing users into SULTAN: $IMPORTED"
        return 0
        ;;

      *)
        echo "Please enter y or n."
        ;;
    esac
  done
}

# ==========================================================
# Legacy SSH login compatibility (same method as old builds)
# ==========================================================
# Old working builds created normal SSH users with /bin/bash and did not
# force a special shell or ForceCommand. Restore that behavior for existing
# SULTAN users before installing the limiter.
rm -f /etc/ssh/sshd_config.d/98-sultan-legacy-login.conf /etc/ssh/sshd_config.d/99-sultan-users.conf
sed -i '\|/usr/local/sbin/sultan-tunnel-shell|d' /etc/shells 2>/dev/null || true

remove_auth_state_name(){
  local FILE="$1" NAME="$2" TMP
  [ -f "$FILE" ] || return 0
  TMP="$(mktemp "$LIMIT_DIR/.auth-state.XXXXXX")" || return 1
  grep -vxF "$NAME" "$FILE" > "$TMP" 2>/dev/null || true
  chmod 600 "$TMP"
  mv -f "$TMP" "$FILE"
}

mkdir -p /run/lock
exec 7>/run/lock/sultan-db.lock
flock -x 7
while IFS='|' read -r EXISTING_USER EXISTING_PASS EXISTING_EXP EXISTING_QUOTA EXISTING_LOGIN; do
  [ -n "$EXISTING_USER" ] || continue
  id "$EXISTING_USER" >/dev/null 2>&1 || continue
  PRIMARY_GROUP="$(id -gn "$EXISTING_USER" 2>/dev/null || true)"
  if [ "$PRIMARY_GROUP" = "sultan-ssh" ]; then
    getent group "$EXISTING_USER" >/dev/null 2>&1 || groupadd "$EXISTING_USER" 2>/dev/null || true
    getent group "$EXISTING_USER" >/dev/null 2>&1 && usermod -g "$EXISTING_USER" "$EXISTING_USER" 2>/dev/null || true
  fi
  usermod -s /bin/bash "$EXISTING_USER" 2>/dev/null || true
  gpasswd -d "$EXISTING_USER" sultan-ssh >/dev/null 2>&1 || true

  case "$EXISTING_EXP" in
    ""|0|Unlimited|unlimited|UNLIMITED)
      chage -d -1 -E -1 -I -1 -m 0 -M 99999 "$EXISTING_USER" 2>/dev/null || true
      ;;
  esac

  case "$EXISTING_QUOTA" in
    ""|0|Unlimited|unlimited|UNLIMITED)
      if [ "$(passwd -S "$EXISTING_USER" 2>/dev/null | awk '{print $2}')" = "L" ]; then
        usermod -U "$EXISTING_USER" 2>/dev/null || {
          [ -n "$EXISTING_PASS" ] && printf '%s:%s\n' "$EXISTING_USER" "$EXISTING_PASS" | chpasswd 2>/dev/null || true
        }
      fi
      remove_auth_state_name "$LIMIT_DIR/blocked.db" "$EXISTING_USER" || true
      remove_auth_state_name "$LIMIT_DIR/quota-locked.db" "$EXISTING_USER" || true
      ;;
  esac
done < "$DB"
flock -u 7
exec 7>&-
rm -f /usr/local/sbin/sultan-tunnel-shell

# ==========================================================
# SSH concurrent-login limiter
# ==========================================================
echo "[2/6] Installing SSH login limiter..."

cat >/usr/local/sbin/sultan-login-limit <<'LOGIN_LIMIT'
#!/bin/bash
set -u

DB="/etc/sultan/users.db"
LIMIT_DIR="/etc/sultan/limits"
DEVICE_DB="$LIMIT_DIR/devices.db"
SESSION_LOG="$LIMIT_DIR/device_sessions.log"
USER_NAME="${PAM_USER:-}"
PAM_ACTION="${PAM_TYPE:-account}"

find_sshd_pid() {
  local pid="${PPID:-0}" comm parent i
  for i in {1..20}; do
    [[ "$pid" =~ ^[0-9]+$ ]] || break
    [ "$pid" -gt 1 ] || break
    comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
    if [ "$comm" = "sshd" ]; then
      echo "$pid"
      return 0
    fi
    parent="$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || true)"
    [ -n "$parent" ] || break
    [ "$parent" != "$pid" ] || break
    pid="$parent"
  done
  return 1
}

safe_value() {
  printf '%s' "${1:-}" | tr '|
' '___'
}

clean_db_value() {
  local VALUE="${1:-}"
  VALUE="${VALUE//$'\r'/}"
  VALUE="${VALUE#"${VALUE%%[![:space:]]*}"}"
  VALUE="${VALUE%"${VALUE##*[![:space:]]}"}"
  printf '%s' "$VALUE"
}

valid_ip_text() {
  case "${1:-}" in
    ""|unknown|UNKNOWN) return 1 ;;
    *[!0-9a-fA-F:.]* ) return 1 ;;
    *) return 0 ;;
  esac
}

ws_value() {
  local KEY="$1" FILE="$2"
  awk -F= -v k="$KEY" '$1==k{print substr($0,index($0,"=")+1);exit}' "$FILE" 2>/dev/null || true
}

sshd_peer_port() {
  local PEER PORT
  PEER="$(ss -tnp 2>/dev/null | awk -v p="$SSHD_PID" '
    $0 ~ "pid="p"," && ($4 ~ /:22$/ || $4 ~ /\]:22$/) {print $5; exit}
  ')"
  [ -n "$PEER" ] || return 1
  PORT="${PEER##*:}"
  [[ "$PORT" =~ ^[0-9]+$ ]] || return 1
  echo "$PORT"
}

resolve_rhost_and_hint() {
  local RH="${PAM_RHOST:-unknown}" PORT MAP IP HINT
  CLIENT_HINT="${SSH_CLIENT:-} ${SSH_CONNECTION:-}"
  REAL_RHOST="$RH"

  case "$RH" in
    127.0.0.1|::1|localhost)
      PORT="$(sshd_peer_port || true)"
      if [ -n "$PORT" ]; then
        MAP="/run/sultan-ws-map/$PORT"
        if [ -f "$MAP" ]; then
          IP="$(ws_value ip "$MAP")"
          HINT="$(ws_value user_agent "$MAP")"
          [ -n "$IP" ] && REAL_RHOST="$IP"
          [ -n "$HINT" ] && CLIENT_HINT="$HINT"
        fi
      fi
      ;;
  esac

  valid_ip_text "$REAL_RHOST" || REAL_RHOST="unknown"
  CLIENT_HINT="$(safe_value "$CLIENT_HINT")"
}

device_id_for() {
  printf '%s' "$USER_NAME|$REAL_RHOST|$CLIENT_HINT" | sha256sum | awk '{print substr($1,1,12)}'
}

device_name_guess() {
  local IP="$1" HINT="$2" OLD_NAME RDNS
  OLD_NAME="$(awk -F'|' -v u="$USER_NAME" -v id="$DEVICE_ID" '$1==u && $2==id{print $3;exit}' "$DEVICE_DB" 2>/dev/null || true)"
  if [ -n "$OLD_NAME" ] && [ "$OLD_NAME" != "Unknown Device" ]; then
    echo "$OLD_NAME"
    return
  fi
  case "$HINT" in
    *iPhone*|*iphone*) echo "iPhone Device"; return ;;
    *iPad*|*ipad*) echo "iPad Device"; return ;;
    *Samsung*|*samsung*) echo "Samsung Device"; return ;;
    *Android*|*android*) echo "Android Device"; return ;;
    *Windows*|*windows*) echo "Windows Device"; return ;;
    *Macintosh*|*macOS*|*darwin*) echo "Mac Device"; return ;;
  esac
  RDNS="$(getent hosts "$IP" 2>/dev/null | awk 'NR==1{print $2}')"
  if [ -n "$RDNS" ]; then
    echo "$(safe_value "$RDNS")"
  else
    echo "Unknown Device"
  fi
}

update_device_login() {
  local NOW FIRST OLD TMP SAFE_NAME SAFE_IP SAFE_HINT
  NOW="$(date +%s)"
  OLD="$(awk -F'|' -v u="$USER_NAME" -v id="$DEVICE_ID" '$1==u && $2==id{print;exit}' "$DEVICE_DB" 2>/dev/null || true)"
  FIRST="$(printf '%s
' "$OLD" | awk -F'|' '{print $5}')"
  [[ "$FIRST" =~ ^[0-9]+$ ]] || FIRST="$NOW"

  SAFE_NAME="$(safe_value "$DEVICE_NAME")"
  SAFE_IP="$(safe_value "$REAL_RHOST")"
  SAFE_HINT="$(safe_value "$CLIENT_HINT")"

  TMP="$(mktemp "$LIMIT_DIR/.devices.XXXXXX")" || return 0
  awk -F'|' -v u="$USER_NAME" -v id="$DEVICE_ID" '!(($1==u)&&($2==id))' "$DEVICE_DB" > "$TMP" 2>/dev/null || true
  printf '%s|%s|%s|%s|%s|%s|%s
' "$USER_NAME" "$DEVICE_ID" "$SAFE_NAME" "$SAFE_IP" "$FIRST" "$NOW" "$SAFE_HINT" >> "$TMP"
  chmod 600 "$TMP"
  mv -f "$TMP" "$DEVICE_DB"
}

write_slot() {
  printf 'user=%s
rhost=%s
created=%s
start=%s
device_id=%s
device_name=%s
client_hint=%s
' \
    "$USER_NAME" "$REAL_RHOST" "$(date +%s)" "$SSHD_START" "$DEVICE_ID" "$DEVICE_NAME" "$CLIENT_HINT" >"$SLOT"
  chmod 600 "$SLOT"
}

close_slot() {
  local START_TS END_TS DUR DID RH
  [ -f "$SLOT" ] || return 0
  START_TS="$(awk -F= '$1=="created"{print $2;exit}' "$SLOT" 2>/dev/null || true)"
  DID="$(awk -F= '$1=="device_id"{print $2;exit}' "$SLOT" 2>/dev/null || true)"
  RH="$(awk -F= '$1=="rhost"{print $2;exit}' "$SLOT" 2>/dev/null || true)"
  [[ "$START_TS" =~ ^[0-9]+$ ]] || START_TS="$(date +%s)"
  [ -n "$DID" ] || DID="unknown"
  [ -n "$RH" ] || RH="unknown"
  END_TS="$(date +%s)"
  DUR=$((END_TS - START_TS))
  [ "$DUR" -lt 0 ] && DUR=0
  printf '%s|%s|%s|%s|%s|%s
' "$USER_NAME" "$DID" "$RH" "$START_TS" "$END_TS" "$DUR" >> "$SESSION_LOG"
  chmod 600 "$SESSION_LOG" 2>/dev/null || true
  rm -f -- "$SLOT"
}

SSHD_PID="$(find_sshd_pid || true)"
[ -n "$SSHD_PID" ] || exit 0
RUNTIME_DIR="/run/sultan-login-slots"
LOCK_FILE="/run/lock/sultan-login-limit.lock"

[ -z "$USER_NAME" ] && exit 0
[ "$USER_NAME" = "root" ] && exit 0
[ -f "$DB" ] || exit 0

mkdir -p "$RUNTIME_DIR" /run/lock "$LIMIT_DIR"
touch "$DEVICE_DB" "$SESSION_LOG"
chmod 700 "$RUNTIME_DIR"
chmod 600 "$DEVICE_DB" "$SESSION_LOG" 2>/dev/null || true

# All checks and slot changes are serialized. This prevents two devices
# authenticating at the same instant from both taking the same final slot.
exec 9>"$LOCK_FILE"
flock -x 9

USER_DIR="$RUNTIME_DIR/$USER_NAME"
mkdir -p "$USER_DIR"
chmod 700 "$USER_DIR"

cleanup_stale_slots() {
  local slot pid cmd saved_start current_start
  shopt -s nullglob
  for slot in "$USER_DIR"/*; do
    pid="${slot##*/}"
    if ! [[ "$pid" =~ ^[0-9]+$ ]] || [ ! -d "/proc/$pid" ]; then
      rm -f -- "$slot"
      continue
    fi
    cmd="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
    saved_start="$(awk -F= '$1=="start"{print $2;exit}' "$slot" 2>/dev/null || true)"
    current_start="$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || true)"
    if [ "$cmd" != "sshd" ] || [ -z "$saved_start" ] || [ "$saved_start" != "$current_start" ]; then
      rm -f -- "$slot"
    fi
  done
  shopt -u nullglob
}

cleanup_stale_slots
SLOT="$USER_DIR/$SSHD_PID"
SSHD_START="$(awk '{print $22}' "/proc/$SSHD_PID/stat" 2>/dev/null || true)"
[ -n "$SSHD_START" ] || exit 0

# PAM close_session is called by the same authenticated sshd process.
# Removing its PID file immediately frees the login slot and saves session duration.
if [ "$PAM_ACTION" = "close_session" ]; then
  /usr/local/sbin/sultan-quota-sync >/dev/null 2>&1 || true
  close_slot
  exit 0
fi

LINE="$(awk -F'|' -v u="$USER_NAME" '$1==u {print; exit}' "$DB" 2>/dev/null)"
[ -n "$LINE" ] || exit 0
MAX="$(printf '%s
' "$LINE" | awk -F'|' '{print $5}')"
QUOTA="$(printf '%s
' "$LINE" | awk -F'|' '{print $4}')"
MAX="$(clean_db_value "$MAX")"
QUOTA="$(clean_db_value "$QUOTA")"
UNLIMITED_LOGIN=0
UNLIMITED_QUOTA=0

case "$QUOTA" in
  ""|0|Unlimited|unlimited|UNLIMITED) UNLIMITED_QUOTA=1 ;;
esac

resolve_rhost_and_hint
DEVICE_ID="$(device_id_for)"
DEVICE_NAME="$(device_name_guess "$REAL_RHOST" "$CLIENT_HINT")"

BLOCKED="/etc/sultan/limits/blocked.db"
if [ "$UNLIMITED_QUOTA" != "1" ] && [ -f "$BLOCKED" ] && grep -qxF "$USER_NAME" "$BLOCKED"; then
  rm -f -- "$SLOT"
  logger -t sultan-login-limit "Rejected blocked quota user=$USER_NAME"
  exit 1
fi

case "$MAX" in
  ""|0|Unlimited|unlimited|UNLIMITED)
    UNLIMITED_LOGIN=1
    ;;
  *[!0-9]*)
    logger -t sultan-login-limit "Rejected user=$USER_NAME invalid_login_limit=$MAX"
    exit 1
    ;;
esac

# open_session must not consume a second slot; it only confirms the slot
# reserved during the account phase.
if [ "$PAM_ACTION" = "open_session" ]; then
  if [ ! -f "$SLOT" ]; then
    update_device_login
    write_slot
  fi
  exit 0
fi

if [ "$UNLIMITED_LOGIN" = "1" ]; then
  update_device_login
  write_slot
  exit 0
fi

# The account phase atomically reserves one slot using this sshd PID.
# Existing files represent live authenticated SSH connections.
ACTIVE="$(find "$USER_DIR" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | wc -l)"

if [ "$ACTIVE" -ge "$MAX" ]; then
  logger -t sultan-login-limit \
    "Rejected user=$USER_NAME active=$ACTIVE limit=$MAX rhost=${REAL_RHOST:-unknown}"
  exit 1
fi

update_device_login
write_slot
exit 0
LOGIN_LIMIT


chmod 700 /usr/local/sbin/sultan-login-limit
chown root:root /usr/local/sbin/sultan-login-limit

if [ -f /etc/pam.d/sshd ]; then
  sed -i '\|/usr/local/sbin/sultan-login-limit|d' /etc/pam.d/sshd
  sed -i '1i session optional pam_exec.so quiet /usr/local/sbin/sultan-login-limit' /etc/pam.d/sshd
  sed -i '1i account required pam_exec.so quiet /usr/local/sbin/sultan-login-limit' /etc/pam.d/sshd
fi

if grep -qE '^[[:space:]]*UsePAM[[:space:]]+' /etc/ssh/sshd_config; then
  sed -i 's/^[[:space:]]*UsePAM[[:space:]].*/UsePAM yes/' /etc/ssh/sshd_config
else
  echo 'UsePAM yes' >> /etc/ssh/sshd_config
fi
# Keep the classic SSH login mode used by the old working builds.
# Do not install a Match Group / ForceCommand rule.
mkdir -p /etc/ssh/sshd_config.d
if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
  sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
fi
rm -f /etc/ssh/sshd_config.d/98-sultan-legacy-login.conf /etc/ssh/sshd_config.d/99-sultan-users.conf
cat >/etc/ssh/sshd_config.d/98-sultan-legacy-login.conf <<'EOF'
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PubkeyAuthentication yes
AuthenticationMethods any
UsePAM yes
AllowTcpForwarding yes
PermitTunnel no
X11Forwarding no
EOF
while IFS='|' read -r EXISTING_USER _; do
  [ -n "$EXISTING_USER" ] || continue
  id "$EXISTING_USER" >/dev/null 2>&1 || continue
  PRIMARY_GROUP="$(id -gn "$EXISTING_USER" 2>/dev/null || true)"
  if [ "$PRIMARY_GROUP" = "sultan-ssh" ]; then
    getent group "$EXISTING_USER" >/dev/null 2>&1 || groupadd "$EXISTING_USER" 2>/dev/null || true
    getent group "$EXISTING_USER" >/dev/null 2>&1 && usermod -g "$EXISTING_USER" "$EXISTING_USER" 2>/dev/null || true
  fi
  usermod -s /bin/bash "$EXISTING_USER" 2>/dev/null || true
  gpasswd -d "$EXISTING_USER" sultan-ssh >/dev/null 2>&1 || true
done < "$DB"

# ==========================================================
# Per-user SSH traffic quota using systemd cgroup IP accounting
# Counts the larger direction per interval to avoid counting
# the same tunneled download twice (server ingress + egress).
# ==========================================================
echo "[3/6] Installing GB quota engine..."

mkdir -p /etc/systemd/system/user-.slice.d
cat >/etc/systemd/system/user-.slice.d/50-sultan-ipaccounting.conf <<'EOF'
[Slice]
IPAccounting=yes
EOF

cat >/usr/local/sbin/sultan-quota-sync <<'QUOTA_SYNC'
#!/bin/bash
set -u
umask 077

DB="/etc/sultan/users.db"
DIR="/etc/sultan/limits"
USAGE="$DIR/usage.db"
BLOCKED="$DIR/blocked.db"
QUOTA_LOCKED="$DIR/quota-locked.db"
DEVICE_USAGE="$DIR/device_usage.db"
LOCK_FILE="/run/lock/sultan-db.lock"

mkdir -p "$DIR" /run/lock
touch "$DB" "$USAGE" "$BLOCKED" "$QUOTA_LOCKED" "$DEVICE_USAGE"
chmod 600 "$DB" "$USAGE" "$BLOCKED" "$QUOTA_LOCKED" "$DEVICE_USAGE"

exec 9>"$LOCK_FILE"
flock -x 9

valid_number() {
  case "${1:-}" in ""|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

to_int() {
  valid_number "${1:-}" || { echo 0; return; }
  echo $((10#$1))
}

save_usage() {
  local U="$1" TOTAL="$2" LAST_IN="$3" LAST_OUT="$4" LAST_NFT="${5:-0}" TMP
  TMP="$(mktemp "$DIR/.usage.XXXXXX")" || return 1
  awk -F'|' -v u="$U" '$1!=u' "$USAGE" > "$TMP" 2>/dev/null || true
  printf '%s|%s|%s|%s|%s
' "$U" "$TOTAL" "$LAST_IN" "$LAST_OUT" "$LAST_NFT" >> "$TMP"
  chmod 600 "$TMP"
  mv -f "$TMP" "$USAGE"
}

remove_blocked_name() {
  local U="$1" TMP
  TMP="$(mktemp "$DIR/.blocked.XXXXXX")" || return 1
  grep -vxF "$U" "$BLOCKED" > "$TMP" 2>/dev/null || true
  chmod 600 "$TMP"
  mv -f "$TMP" "$BLOCKED"
}

remove_quota_locked_name() {
  local U="$1" TMP
  TMP="$(mktemp "$DIR/.quota-locked.XXXXXX")" || return 1
  grep -vxF "$U" "$QUOTA_LOCKED" > "$TMP" 2>/dev/null || true
  chmod 600 "$TMP"
  mv -f "$TMP" "$QUOTA_LOCKED"
}

shadow_locked() {
  local U="$1" P
  P="$(awk -F: -v u="$U" '$1==u{print $2;exit}' /etc/shadow 2>/dev/null)"
  case "$P" in \!*|\*) return 0 ;; *) return 1 ;; esac
}

slice_counters() {
  local UIDN="$1"
  local UNIT="user-${UIDN}.slice"
  local IN OUT

  IN="$(systemctl show "$UNIT" -p IPIngressBytes --value 2>/dev/null || true)"
  OUT="$(systemctl show "$UNIT" -p IPEgressBytes --value 2>/dev/null || true)"

  valid_number "$IN" || IN=0
  valid_number "$OUT" || OUT=0

  printf '%s|%s
' "$(to_int "$IN")" "$(to_int "$OUT")"
}

nft_counter_name() {
  printf 'u_%s_out
' "$1"
}

ensure_nft_counter() {
  local UIDN="$1" NAME RULES
  command -v nft >/dev/null 2>&1 || return 1
  NAME="$(nft_counter_name "$UIDN")"

  nft list table inet sultan_quota >/dev/null 2>&1 || nft add table inet sultan_quota >/dev/null 2>&1 || return 1
  nft list chain inet sultan_quota output >/dev/null 2>&1 || \
    nft add chain inet sultan_quota output '{ type filter hook output priority filter; policy accept; }' >/dev/null 2>&1 || return 1
  nft list counter inet sultan_quota "$NAME" >/dev/null 2>&1 || \
    nft add counter inet sultan_quota "$NAME" >/dev/null 2>&1 || return 1

  RULES="$(nft list chain inet sultan_quota output 2>/dev/null || true)"
  printf '%s
' "$RULES" | grep -q "meta skuid $UIDN counter name \"$NAME\"" || \
    nft add rule inet sultan_quota output meta skuid "$UIDN" counter name "$NAME" >/dev/null 2>&1 || true
  return 0
}

nft_counter_bytes() {
  local UIDN="$1" NAME BYTES
  command -v nft >/dev/null 2>&1 || { echo 0; return; }
  command -v jq >/dev/null 2>&1 || { echo 0; return; }
  NAME="$(nft_counter_name "$UIDN")"
  BYTES="$(nft -j list counter inet sultan_quota "$NAME" 2>/dev/null | jq -r '.. | objects | select(has("bytes")) | .bytes' 2>/dev/null | head -n1)"
  valid_number "$BYTES" || BYTES=0
  echo "$BYTES"
}

quota_to_bytes() {
  local Q="$1" N
  case "$Q" in
    ""|0|Unlimited|unlimited|UNLIMITED) echo 0 ;;
    *GB|*gb|*Gb|*gB)
      N="${Q%??}"
      valid_number "$N" && echo $(( $(to_int "$N") * 1024 * 1024 * 1024 )) || echo 0
      ;;
    *)
      valid_number "$Q" && echo $(( $(to_int "$Q") * 1024 * 1024 * 1024 )) || echo 0
      ;;
  esac
}

save_device_usage_one() {
  local U="$1" ID="$2" ADD="$3" TODAY MONTH OLD TOTAL DAYKEY DAYBYTES MONTHKEY MONTHBYTES TMP
  valid_number "$ADD" || ADD=0
  [ "$ADD" -gt 0 ] || return 0
  TODAY="$(date +%F)"
  MONTH="$(date +%Y-%m)"
  OLD="$(awk -F'|' -v u="$U" -v id="$ID" '$1==u && $2==id{print;exit}' "$DEVICE_USAGE" 2>/dev/null || true)"
  TOTAL="$(printf '%s
' "$OLD" | awk -F'|' '{print $3}')"
  DAYKEY="$(printf '%s
' "$OLD" | awk -F'|' '{print $4}')"
  DAYBYTES="$(printf '%s
' "$OLD" | awk -F'|' '{print $5}')"
  MONTHKEY="$(printf '%s
' "$OLD" | awk -F'|' '{print $6}')"
  MONTHBYTES="$(printf '%s
' "$OLD" | awk -F'|' '{print $7}')"
  valid_number "$TOTAL" || TOTAL=0
  valid_number "$DAYBYTES" || DAYBYTES=0
  valid_number "$MONTHBYTES" || MONTHBYTES=0
  [ "$DAYKEY" = "$TODAY" ] || DAYBYTES=0
  [ "$MONTHKEY" = "$MONTH" ] || MONTHBYTES=0
  TOTAL=$((TOTAL + ADD))
  DAYBYTES=$((DAYBYTES + ADD))
  MONTHBYTES=$((MONTHBYTES + ADD))

  TMP="$(mktemp "$DIR/.device_usage.XXXXXX")" || return 1
  awk -F'|' -v u="$U" -v id="$ID" '!(($1==u)&&($2==id))' "$DEVICE_USAGE" > "$TMP" 2>/dev/null || true
  printf '%s|%s|%s|%s|%s|%s|%s
' "$U" "$ID" "$TOTAL" "$TODAY" "$DAYBYTES" "$MONTH" "$MONTHBYTES" >> "$TMP"
  chmod 600 "$TMP"
  mv -f "$TMP" "$DEVICE_USAGE"
}

active_device_ids_for_user() {
  local U="$1" DIRS="/run/sultan-login-slots/$U" SLOT ID PID CMD SAVED_START CURRENT_START
  [ -d "$DIRS" ] || return 0
  shopt -s nullglob
  for SLOT in "$DIRS"/*; do
    PID="${SLOT##*/}"
    [[ "$PID" =~ ^[0-9]+$ ]] || continue
    [ -d "/proc/$PID" ] || continue
    CMD="$(cat "/proc/$PID/comm" 2>/dev/null || true)"
    SAVED_START="$(awk -F= '$1=="start"{print $2;exit}' "$SLOT" 2>/dev/null || true)"
    CURRENT_START="$(awk '{print $22}' "/proc/$PID/stat" 2>/dev/null || true)"
    [ "$CMD" = "sshd" ] || continue
    [ -n "$SAVED_START" ] && [ "$SAVED_START" = "$CURRENT_START" ] || continue
    ID="$(awk -F= '$1=="device_id"{print $2;exit}' "$SLOT" 2>/dev/null || true)"
    [ -n "$ID" ] && printf '%s
' "$ID"
  done | sort -u
  shopt -u nullglob
}

attribute_device_usage() {
  local U="$1" DELTA="$2" IDS N SHARE REM I ADD
  valid_number "$DELTA" || DELTA=0
  [ "$DELTA" -gt 0 ] || return 0
  mapfile -t IDS < <(active_device_ids_for_user "$U")
  N="${#IDS[@]}"
  [ "$N" -gt 0 ] || return 0
  SHARE=$((DELTA / N))
  REM=$((DELTA % N))
  for I in "${!IDS[@]}"; do
    ADD="$SHARE"
    if [ "$REM" -gt 0 ]; then
      ADD=$((ADD + 1))
      REM=$((REM - 1))
    fi
    save_device_usage_one "$U" "${IDS[$I]}" "$ADD"
  done
}

# Remove stale users.
while IFS='|' read -r OLD_USER _; do
  [ -n "$OLD_USER" ] || continue
  if ! grep -q "^${OLD_USER}|" "$DB" 2>/dev/null; then
    remove_blocked_name "$OLD_USER"
    remove_quota_locked_name "$OLD_USER"
    awk -F'|' -v u="$OLD_USER" '$1!=u' "$USAGE" > "$USAGE.tmp" 2>/dev/null || true
    mv "$USAGE.tmp" "$USAGE"
  fi
done < "$USAGE"

while IFS='|' read -r U PASS EXP QUOTA MAXLOGIN; do
  [ -n "$U" ] || continue
  id "$U" >/dev/null 2>&1 || continue

  UIDN="$(id -u "$U")"
  UNIT="user-${UIDN}.slice"
  systemctl set-property --runtime "$UNIT" IPAccounting=yes >/dev/null 2>&1 || true
  ensure_nft_counter "$UIDN" >/dev/null 2>&1 || true

  COUNTERS="$(slice_counters "$UIDN")"
  CUR_IN="${COUNTERS%%|*}"
  CUR_OUT="${COUNTERS##*|}"
  CUR_NFT="$(nft_counter_bytes "$UIDN")"

  OLD="$(awk -F'|' -v u="$U" '$1==u{print;exit}' "$USAGE")"
  TOTAL="$(printf '%s
' "$OLD" | awk -F'|' '{print $2}')"
  LAST_IN="$(printf '%s
' "$OLD" | awk -F'|' '{print $3}')"
  LAST_OUT="$(printf '%s
' "$OLD" | awk -F'|' '{print $4}')"
  LAST_NFT="$(printf '%s
' "$OLD" | awk -F'|' '{print $5}')"

  TOTAL="$(to_int "$TOTAL")"
  LAST_IN="$(to_int "$LAST_IN")"
  LAST_OUT="$(to_int "$LAST_OUT")"
  LAST_NFT="$(to_int "$LAST_NFT")"
  CUR_IN="$(to_int "$CUR_IN")"
  CUR_OUT="$(to_int "$CUR_OUT")"
  CUR_NFT="$(to_int "$CUR_NFT")"

  if [ "$CUR_IN" -ge "$LAST_IN" ]; then
    DELTA_IN=$((CUR_IN - LAST_IN))
  else
    DELTA_IN="$CUR_IN"
  fi

  if [ "$CUR_OUT" -ge "$LAST_OUT" ]; then
    DELTA_OUT=$((CUR_OUT - LAST_OUT))
  else
    DELTA_OUT="$CUR_OUT"
  fi

  if [ "$CUR_NFT" -ge "$LAST_NFT" ]; then
    DELTA_NFT=$((CUR_NFT - LAST_NFT))
  else
    DELTA_NFT="$CUR_NFT"
  fi

  # SSH tunnel traffic crosses the server in both directions.
  # Count only the larger side during each interval to avoid double counting.
  # If systemd IPAccounting is unavailable, nftables skuid output counters are used as a fallback.
  if [ "$DELTA_IN" -ge "$DELTA_OUT" ]; then
    DELTA="$DELTA_IN"
  else
    DELTA="$DELTA_OUT"
  fi
  if [ "$DELTA_NFT" -gt "$DELTA" ]; then
    DELTA="$DELTA_NFT"
  fi

  TOTAL=$((TOTAL + DELTA))
  save_usage "$U" "$TOTAL" "$CUR_IN" "$CUR_OUT" "$CUR_NFT"
  attribute_device_usage "$U" "$DELTA"

  LIMIT="$(quota_to_bytes "$QUOTA")"

  if [ "$LIMIT" -eq 0 ]; then
    # A real 0 is unlimited. Repair every quota lock left by older builds so
    # password authentication cannot intermittently fail for unlimited users.
    WAS_QUOTA_STATE=0
    grep -qxF "$U" "$BLOCKED" 2>/dev/null && WAS_QUOTA_STATE=1
    grep -qxF "$U" "$QUOTA_LOCKED" 2>/dev/null && WAS_QUOTA_STATE=1
    shadow_locked "$U" && WAS_QUOTA_STATE=1

    if [ "$WAS_QUOTA_STATE" = "1" ]; then
      if shadow_locked "$U"; then
        usermod -U "$U" 2>/dev/null || {
          [ -n "$PASS" ] && printf '%s:%s\n' "$U" "$PASS" | chpasswd 2>/dev/null || true
        }
      fi
      remove_quota_locked_name "$U"
      remove_blocked_name "$U"
      logger -t sultan-quota "Repaired unlimited user=$U limit=0"
    fi
  elif [ "$TOTAL" -ge "$LIMIT" ]; then
    if ! grep -qxF "$U" "$BLOCKED"; then
      echo "$U" >> "$BLOCKED"
      chmod 600 "$BLOCKED"
      if ! shadow_locked "$U"; then
        usermod -L "$U" 2>/dev/null || true
        grep -qxF "$U" "$QUOTA_LOCKED" 2>/dev/null || echo "$U" >> "$QUOTA_LOCKED"
        chmod 600 "$QUOTA_LOCKED"
      fi
      loginctl terminate-user "$UIDN" 2>/dev/null || true
      pkill -KILL -u "$U" 2>/dev/null || true
      logger -t sultan-quota "Blocked user=$U used=$TOTAL limit=$LIMIT"
    fi
  else
    if grep -qxF "$U" "$BLOCKED"; then
      if shadow_locked "$U"; then
        usermod -U "$U" 2>/dev/null || {
          [ -n "$PASS" ] && printf '%s:%s\n' "$U" "$PASS" | chpasswd 2>/dev/null || true
        }
      fi
      remove_quota_locked_name "$U"
      remove_blocked_name "$U"
      logger -t sultan-quota "Unblocked user=$U used=$TOTAL limit=$LIMIT"
    fi
  fi
done < "$DB"
QUOTA_SYNC

chmod 700 /usr/local/sbin/sultan-quota-sync
chown root:root /usr/local/sbin/sultan-quota-sync

cat >/etc/systemd/system/sultan-quota.service <<'EOF'
[Unit]
Description=SULTAN per-user SSH bandwidth quota
After=network-online.target systemd-logind.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sultan-quota-sync
EOF

cat >/etc/systemd/system/sultan-quota.timer <<'EOF'
[Unit]
Description=SULTAN quota checker

[Timer]
OnBootSec=10s
OnUnitActiveSec=3s
AccuracySec=1s
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reset old incompatible counters once when upgrading.
if [ ! -f "$LIMIT_DIR/.quota-v2" ]; then
  : > "$LIMIT_DIR/usage.db"
  touch "$LIMIT_DIR/.quota-v2"
fi

# ==========================================================
# Main panel
# ==========================================================
echo "[4/6] Writing full menu panel..."

cat > "$PANEL" <<'PANEL'
#!/bin/bash

# Running the panel with 'source menu' would allow an exit statement to close
# the parent SSH shell. Always execute it normally with: menu
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "Run the panel normally with: menu"
  return 1
fi

umask 077
trap 'printf "\nCancelled. Returning to the menu.\n"' INT

BASE="/etc/sultan"
DB="$BASE/users.db"
DOMAIN_FILE="$BASE/domain"
XDB="$BASE/xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
USAGE_DB="$BASE/limits/usage.db"
DEVICE_DB="$BASE/limits/devices.db"
DEVICE_USAGE_DB="$BASE/limits/device_usage.db"
DEVICE_SESSIONS="$BASE/limits/device_sessions.log"
WS_TOKEN_FILE="$BASE/ws_token"

mkdir -p "$BASE" "$XDB" "$BASE/limits"
touch "$DB" "$USAGE_DB" "$DEVICE_DB" "$DEVICE_USAGE_DB" "$DEVICE_SESSIONS"
touch "$BASE/limits/blocked.db"
touch "$BASE/limits/quota-locked.db"
chmod 700 "$BASE" "$XDB" "$BASE/limits" 2>/dev/null || true
chmod 600 "$DB" "$USAGE_DB" "$BASE/limits/blocked.db" "$BASE/limits/quota-locked.db" "$DEVICE_DB" "$DEVICE_USAGE_DB" "$DEVICE_SESSIONS" 2>/dev/null || true

DB_LOCK="/run/lock/sultan-db.lock"
mkdir -p /run/lock

current_sshd_pid(){
  local P="${PPID:-0}" C NEXT I
  for I in {1..30}; do
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

current_session_via_ws(){
  local REMOTE="${SSH_CONNECTION%% *}"
  case "$REMOTE" in
    127.0.0.1|::1|localhost) return 0 ;;
  esac
  return 1
}

defer_command_until_logout(){
  local NAME="$1" CMD="$2" PID UNIT
  PID="$(current_sshd_pid || true)"
  [[ "$PID" =~ ^[0-9]+$ ]] || return 1
  UNIT="sultan-${NAME}-after-ssh-${PID}"
  systemctl reset-failed "$UNIT.service" >/dev/null 2>&1 || true
  systemd-run --quiet --collect --unit="$UNIT" /bin/bash -c     "while kill -0 $PID 2>/dev/null; do sleep 3; done; $CMD" >/dev/null 2>&1
}

defer_ws_restart_until_logout(){
  defer_command_until_logout "ws-restart" "systemctl restart sultan-ws"
}

checked_restart(){
  local S="$1"
  case "$S" in
    nginx|haproxy)
      # Reload keeps established tunnels alive. Restart is used only when the
      # service is not active or reload is unavailable.
      if systemctl is-active --quiet "$S" 2>/dev/null; then
        systemctl reload "$S" 2>/dev/null || systemctl restart "$S" 2>/dev/null || {
          echo "$S service failed. Check: journalctl -u $S --no-pager"
          return 1
        }
      else
        systemctl restart "$S" 2>/dev/null || {
          echo "$S service failed. Check: journalctl -u $S --no-pager"
          return 1
        }
      fi
      ;;
    sultan-ws)
      # Restarting the WebSocket daemon would cut the management connection
      # when this SSH session itself arrived through that daemon. Keep the old
      # worker alive and restart automatically after this SSH session closes.
      if current_session_via_ws; then
        systemctl enable sultan-ws >/dev/null 2>&1 || true
        defer_ws_restart_until_logout || true
        echo "Current SSH session uses WebSocket; sultan-ws restart was skipped now and deferred until logout."
        return 0
      fi
      systemctl restart "$S" 2>/dev/null || {
        echo "$S service failed. Check: journalctl -u $S --no-pager"
        return 1
      }
      ;;
    *)
      systemctl restart "$S" 2>/dev/null || {
        echo "$S service failed. Check: journalctl -u $S --no-pager"
        return 1
      }
      ;;
  esac
}

checked_enable_now(){
  local S="$1"
  systemctl enable "$S" >/dev/null 2>&1 || true
  checked_restart "$S"
}

nft_user_counter_bytes(){
  local UIDN="$1" NAME BYTES
  command -v nft >/dev/null 2>&1 || { echo 0; return; }
  command -v jq >/dev/null 2>&1 || { echo 0; return; }
  NAME="u_${UIDN}_out"
  BYTES="$(nft -j list counter inet sultan_quota "$NAME" 2>/dev/null | jq -r '.. | objects | select(has("bytes")) | .bytes' 2>/dev/null | head -n1)"
  [[ "$BYTES" =~ ^[0-9]+$ ]] || BYTES=0
  echo "$BYTES"
}

db_update_field(){
  local U="$1" FIELD="$2" VALUE="$3" TMP
  (
    flock -x 8
    TMP="$(mktemp "$BASE/.users.XXXXXX")" || exit 1
    awk -F'|' -v u="$U" -v f="$FIELD" -v v="$VALUE" '
      BEGIN{OFS="|"; found=0}
      $1==u{$f=v; found=1}
      {print}
      END{if(!found) exit 2}
    ' "$DB" > "$TMP" || { rm -f "$TMP"; exit 1; }
    chmod 600 "$TMP"
    mv -f "$TMP" "$DB"
  ) 8>"$DB_LOCK"
}

db_remove_user(){
  local U="$1" TMP
  (
    flock -x 8
    TMP="$(mktemp "$BASE/.users.XXXXXX")" || exit 1
    awk -F'|' -v u="$U" '$1!=u' "$DB" > "$TMP" || { rm -f "$TMP"; exit 1; }
    chmod 600 "$TMP"
    mv -f "$TMP" "$DB"
  ) 8>"$DB_LOCK"
}

db_add_user(){
  local LINE="$1" TMP
  (
    flock -x 8
    TMP="$(mktemp "$BASE/.users.XXXXXX")" || exit 1
    awk -F'|' -v u="${LINE%%|*}" '$1!=u' "$DB" > "$TMP" || { rm -f "$TMP"; exit 1; }
    printf '%s\n' "$LINE" >> "$TMP"
    chmod 600 "$TMP"
    mv -f "$TMP" "$DB"
  ) 8>"$DB_LOCK"
}

usage_reset_user(){
  local U="$1" UIDN CUR_IN CUR_OUT CUR_NFT TMP
  UIDN="$(id -u "$U" 2>/dev/null || true)"
  [ -n "$UIDN" ] || return 1
  CUR_IN="$(systemctl show "user-${UIDN}.slice" -p IPIngressBytes --value 2>/dev/null || echo 0)"
  CUR_OUT="$(systemctl show "user-${UIDN}.slice" -p IPEgressBytes --value 2>/dev/null || echo 0)"
  CUR_NFT="$(nft_user_counter_bytes "$UIDN")"
  [[ "$CUR_IN" =~ ^[0-9]+$ ]] || CUR_IN=0
  [[ "$CUR_OUT" =~ ^[0-9]+$ ]] || CUR_OUT=0
  [[ "$CUR_NFT" =~ ^[0-9]+$ ]] || CUR_NFT=0

  (
    flock -x 8
    TMP="$(mktemp "$BASE/limits/.usage.XXXXXX")" || exit 1
    awk -F'|' -v u="$U" '$1!=u' "$USAGE_DB" > "$TMP" 2>/dev/null || true
    printf '%s|0|%s|%s|%s\n' "$U" "$CUR_IN" "$CUR_OUT" "$CUR_NFT" >> "$TMP"
    chmod 600 "$TMP"
    mv -f "$TMP" "$USAGE_DB"

    TMP="$(mktemp "$BASE/limits/.blocked.XXXXXX")" || exit 1
    grep -vxF "$U" "$BASE/limits/blocked.db" > "$TMP" 2>/dev/null || true
    chmod 600 "$TMP"
    mv -f "$TMP" "$BASE/limits/blocked.db"

    if grep -qxF "$U" "$BASE/limits/quota-locked.db" 2>/dev/null; then
      usermod -U "$U" 2>/dev/null || true
      TMP="$(mktemp "$BASE/limits/.quota-locked.XXXXXX")" || exit 1
      grep -vxF "$U" "$BASE/limits/quota-locked.db" > "$TMP" 2>/dev/null || true
      chmod 600 "$TMP"
      mv -f "$TMP" "$BASE/limits/quota-locked.db"
    fi
  ) 8>"$DB_LOCK"
}

cleanup_managed_user_records(){
  local U="$1" TMP
  (
    flock -x 8
    TMP="$(mktemp "$BASE/limits/.usage.XXXXXX")" || exit 1
    awk -F'|' -v u="$U" '$1!=u' "$USAGE_DB" > "$TMP" 2>/dev/null || true
    chmod 600 "$TMP"
    mv -f "$TMP" "$USAGE_DB"

    TMP="$(mktemp "$BASE/limits/.blocked.XXXXXX")" || exit 1
    grep -vxF "$U" "$BASE/limits/blocked.db" > "$TMP" 2>/dev/null || true
    chmod 600 "$TMP"
    mv -f "$TMP" "$BASE/limits/blocked.db"

    TMP="$(mktemp "$BASE/limits/.quota-locked.XXXXXX")" || exit 1
    grep -vxF "$U" "$BASE/limits/quota-locked.db" > "$TMP" 2>/dev/null || true
    chmod 600 "$TMP"
    mv -f "$TMP" "$BASE/limits/quota-locked.db"
  ) 8>"$DB_LOCK"
}

managed_ssh_user_exists(){
  local U="$1"
  awk -F'|' -v u="$U" '$1==u{found=1} END{exit !found}' "$DB" 2>/dev/null &&
  id "$U" >/dev/null 2>&1
}

delete_managed_ssh_user(){
  local U="$1" UIDN
  managed_ssh_user_exists "$U" || { echo "User is not managed by SULTAN."; return 1; }
  UIDN="$(id -u "$U" 2>/dev/null || true)"
  [ -n "$UIDN" ] && loginctl terminate-user "$UIDN" 2>/dev/null || true
  pkill -KILL -u "$U" 2>/dev/null || true
  userdel -r "$U" 2>/dev/null || { echo "Failed to delete system user: $U"; return 1; }
  db_remove_user "$U" || { echo "Failed to update users DB."; return 1; }
  cleanup_managed_user_records "$U"
  quota_sync
}

validate_username(){
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] &&
  ! [[ "$1" =~ [|[:space:]] ]]
}

validate_password(){
  [ -n "$1" ] &&
  ! [[ "$1" == *"|"* ]] &&
  ! [[ "$1" == *$'\n'* ]] &&
  ! [[ "$1" == *$'\r'* ]]
}

validate_domain(){
  [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

validate_ipv4(){
  local IFS=. A B C D O
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r A B C D <<< "$1"
  for O in "$A" "$B" "$C" "$D"; do
    [[ "$O" =~ ^[0-9]+$ ]] || return 1
    [ "$O" -ge 0 ] && [ "$O" -le 255 ] || return 1
  done
  return 0
}

validate_link_address(){
  validate_domain "$1" || validate_ipv4 "$1"
}

validate_xray_username(){
  [[ "$1" =~ ^[A-Za-z0-9_.-]{1,64}$ ]] &&
  ! [[ "$1" == *"|"* ]]
}

validate_ws_path(){
  local P="${1:-}"
  [ -n "$P" ] || return 1
  [ "${#P}" -le 128 ] || return 1

  # URL-safe ASCII path segments. Examples:
  # /vless
  # /sultan
  # /vpn/vless
  # /abc-123_test
  [[ "$P" =~ ^/[A-Za-z0-9._~-]+(/[A-Za-z0-9._~-]+)*$ ]] || return 1
  [ "$P" != "/" ] || return 1

  # Keep reserved internal paths protected.
  case "$P" in
    /.well-known|/.well-known/*|/sshws|/sshws-*|/sultan-ssh|/sultan-ssh* ) return 1 ;;
  esac

  return 0
}

normalize_ws_path(){
  local P="${1:-}"

  # Trim spaces and line endings.
  P="$(printf '%s' "$P" | tr -d '\r\n"'"'"'`' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  # If user pastes a full URL, keep only its path.
  case "$P" in
    http://*|https://*)
      P="$(printf '%s' "$P" | sed -E 's#^[a-zA-Z]+://[^/]+##; s#[?#].*$##')"
      ;;
  esac

  # Drop query/hash if pasted accidentally.
  P="${P%%\?*}"
  P="${P%%#*}"

  # Accept simple words like "vless" and convert them to "/vless".
  [ -n "$P" ] || return 1
  [ "${P:0:1}" = "/" ] || P="/$P"

  # Collapse repeated slashes and remove trailing slash.
  P="$(printf '%s' "$P" | sed -E 's#/+#/#g; s#/$##')"
  [ -n "$P" ] || return 1

  validate_ws_path "$P" || return 1
  printf '%s\n' "$P"
}

xray_default_path(){
  case "$1" in
    vless-ws) echo "/vless-ws" ;;
    vmess-ws) echo "/vmess-ws" ;;
    trojan-ws) echo "/trojan-ws" ;;
    *) echo "/xray-ws" ;;
  esac
}

xray_current_path(){
  local TAG="$1" FALLBACK="${2:-}" P
  [ -n "$FALLBACK" ] || FALLBACK="$(xray_default_path "$TAG")"
  P="$(jq -r --arg tag "$TAG" '.inbounds[]? | select(.tag==$tag) | .streamSettings.wsSettings.path // empty' "$XRAY_CONFIG" 2>/dev/null | head -n1)"
  validate_ws_path "$P" || P="$FALLBACK"
  printf '%s\n' "$P"
}

xray_saved_path(){
  local TAG="$1" FALLBACK P
  FALLBACK="$(xray_default_path "$TAG")"
  P="$(awk -F'|' 'NF>=6 && $6!="" {print $6; exit}' "$XDB/$TAG.db" 2>/dev/null || true)"
  validate_ws_path "$P" || P="$FALLBACK"
  printf '%s\n' "$P"
}

xray_path_used_by_other(){
  local TAG="$1" PATHX="$2"
  jq -e --arg tag "$TAG" --arg path "$PATHX" '
    any(.inbounds[]?;
      .tag != $tag and
      (.tag=="vless-ws" or .tag=="vmess-ws" or .tag=="trojan-ws") and
      (.streamSettings.wsSettings.path // "") == $path
    )
  ' "$XRAY_CONFIG" >/dev/null 2>&1
}

xray_db_set_path_all(){
  local DBF="$1" PATHX="$2" TMP LOCKF
  [ -f "$DBF" ] || return 0
  LOCKF="${DBF}.lock"
  (
    flock -x 7
    TMP="$(mktemp "$XDB/.xraypath.XXXXXX")" || exit 1
    awk -F'|' -v p="$PATHX" '
      BEGIN{OFS="|"}
      NF {
        while(NF<10) $(NF+1)=""
        $6=p
      }
      {print}
    ' "$DBF" > "$TMP" || { rm -f "$TMP"; exit 1; }
    chmod 600 "$TMP"
    mv -f "$TMP" "$DBF"
  ) 7>"$LOCKF"
}

current_tls_files(){
  local D="$1"
  if [ -f "/etc/letsencrypt/live/$D/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$D/privkey.pem" ]; then
    printf '%s|%s\n' "/etc/letsencrypt/live/$D/fullchain.pem" "/etc/letsencrypt/live/$D/privkey.pem"
  else
    [ -f "/etc/sultan/selfsigned/$D/fullchain.pem" ] || create_self_signed_cert "$D"
    printf '%s|%s\n' "/etc/sultan/selfsigned/$D/fullchain.pem" "/etc/sultan/selfsigned/$D/privkey.pem"
  fi
}

refresh_proxy_config_from_current(){
  local D FILES CERT KEY TOKEN
  D="$(get_domain)"
  [ -n "$D" ] && [ "$D" != "Not Set" ] && validate_domain "$D" || {
    echo "A valid domain is required before updating WebSocket paths."
    return 1
  }
  FILES="$(current_tls_files "$D")" || return 1
  CERT="${FILES%%|*}"
  KEY="${FILES##*|}"
  TOKEN="$(ensure_ws_token)"
  write_nginx_config "$D" "$CERT" "$KEY" "$TOKEN"
  write_haproxy_config
  nginx_haproxy_restart_safe
}

xray_set_protocol_path(){
  local TAG="$1" NEW_PATH="$2" DBF="$3" OLD_PATH CFG_BACKUP DB_BACKUP=""
  NEW_PATH="$(normalize_ws_path "$NEW_PATH")" || {
    echo "Invalid path. Use letters, numbers, dot, underscore, dash, tilde and slash only."
    echo "You can type: /vless-ws  or  vless  or  /vless  or  /vpn/vless"
    echo "Do not use spaces."
    return 1
  }
  OLD_PATH="$(xray_current_path "$TAG" "$(xray_default_path "$TAG")")"
  [ "$NEW_PATH" = "$OLD_PATH" ] && return 0
  if xray_path_used_by_other "$TAG" "$NEW_PATH"; then
    echo "This path is already used by another Xray protocol."
    return 1
  fi

  CFG_BACKUP="$(mktemp --suffix=.json "/usr/local/etc/xray/.path-rollback.XXXXXX")" || return 1
  cp -a "$XRAY_CONFIG" "$CFG_BACKUP" || { rm -f "$CFG_BACKUP"; return 1; }
  if [ -f "$DBF" ]; then
    DB_BACKUP="$(mktemp "$XDB/.path-db-rollback.XXXXXX")" || { rm -f "$CFG_BACKUP"; return 1; }
    cp -a "$DBF" "$DB_BACKUP" || { rm -f "$CFG_BACKUP" "$DB_BACKUP"; return 1; }
  fi

  if ! xray_jq_update '
    (.inbounds[] | select(.tag==$tag) | .streamSettings.network) = "ws" |
    del(.inbounds[] | select(.tag==$tag) | .streamSettings.method) |
    (.inbounds[] | select(.tag==$tag) | .streamSettings.wsSettings.path) = $path
  ' --arg tag "$TAG" --arg path "$NEW_PATH"; then
    rm -f "$CFG_BACKUP" "$DB_BACKUP"
    echo "Xray rejected the new WebSocket path."
    return 1
  fi

  xray_db_set_path_all "$DBF" "$NEW_PATH" || {
    cp -a "$CFG_BACKUP" "$XRAY_CONFIG"
    [ -n "$DB_BACKUP" ] && cp -a "$DB_BACKUP" "$DBF"
    rm -f "$CFG_BACKUP" "$DB_BACKUP"
    return 1
  }

  if ! xray_restart_safe || ! refresh_proxy_config_from_current; then
    cp -a "$CFG_BACKUP" "$XRAY_CONFIG"
    [ -n "$DB_BACKUP" ] && cp -a "$DB_BACKUP" "$DBF"
    xray_restart_safe >/dev/null 2>&1 || true
    refresh_proxy_config_from_current >/dev/null 2>&1 || true
    rm -f "$CFG_BACKUP" "$DB_BACKUP"
    echo "Path change failed and was rolled back."
    return 1
  fi

  rm -f "$CFG_BACKUP" "$DB_BACKUP"
  echo "WebSocket path changed: $OLD_PATH -> $NEW_PATH"
  return 0
}

ensure_ws_token(){
  if [ ! -s "$WS_TOKEN_FILE" ]; then
    openssl rand -hex 24 > "$WS_TOKEN_FILE"
  fi
  chmod 600 "$WS_TOKEN_FILE"
  cat "$WS_TOKEN_FILE"
}

restore_legacy_ssh_login(){
  local U="$1" PRIMARY_GROUP
  id "$U" >/dev/null 2>&1 || return 1
  PRIMARY_GROUP="$(id -gn "$U" 2>/dev/null || true)"
  if [ "$PRIMARY_GROUP" = "sultan-ssh" ]; then
    getent group "$U" >/dev/null 2>&1 || groupadd "$U" 2>/dev/null || true
    getent group "$U" >/dev/null 2>&1 && usermod -g "$U" "$U" 2>/dev/null || true
  fi
  usermod -s /bin/bash "$U" 2>/dev/null || return 1
  gpasswd -d "$U" sultan-ssh >/dev/null 2>&1 || true
  return 0
}

safe_restart_ssh(){
  if ! sshd -t; then
    echo "SSH config error. Restart skipped."
    return 1
  fi
  if current_session_via_ws; then
    echo "Current SSH session uses WebSocket; SSH reload skipped to protect this session."
    return 0
  fi
  systemctl reload ssh 2>/dev/null || systemctl reload sshd
  return 0
}

total_online_logins(){
  local U TOTAL=0 N
  while IFS='|' read -r U _; do
    [ -n "$U" ] || continue
    N="$(active_user_logins "$U")"
    [[ "$N" =~ ^[0-9]+$ ]] || N=0
    TOTAL=$((TOTAL + N))
  done < "$DB"
  echo "$TOTAL"
}

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
ORANGE="\e[38;5;208m"
BLUE="\e[34m"
MAG="\e[35m"
CYAN="\e[36m"
WHITE="\e[97m"
NC="\e[0m"

refresh_screen(){ printf '\033c'; printf '\033[2J\033[3J\033[H'; clear; }
pause(){
  echo ""
  [ "${SULTAN_NONINTERACTIVE:-0}" = "1" ] && return 0

  # Do not return automatically while the user is copying a link or
  # reading account details. Wait for a real Enter key from the terminal.
  if [ -r /dev/tty ]; then
    IFS= read -r -p "Press Enter..." x </dev/tty || true
  elif [ -t 0 ]; then
    IFS= read -r -p "Press Enter..." x || true
  else
    return 0
  fi

  echo ""
  return 0
}
box(){ printf "%-16s :      [ %s ]\n" "$1" "$2"; }
svc(){ systemctl is-active --quiet "$1" 2>/dev/null && echo ACTIVE || echo OFFLINE; }

badge(){
  case "$1" in
    ACTIVE|READY|OK) echo -e "${GREEN}$1${NC}" ;;
    OFFLINE|FAILED|MISSING) echo -e "${RED}$1${NC}" ;;
    *) echo -e "${YELLOW}$1${NC}" ;;
  esac
}

svc_badge(){ badge "$(svc "$1")"; }
get_domain(){ cat "$DOMAIN_FILE" 2>/dev/null || echo "Not Set"; }

get_ip(){
  local IP
  IP="$(curl -s --max-time 4 ipv4.icanhazip.com 2>/dev/null | tr -d '\n')"
  [ -n "$IP" ] && echo "$IP" || hostname -I | awk '{print $1}'
}

get_os(){ lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"'; }
get_ram(){ free -m | awk '/Mem:/ {print $3"MB / "$2"MB"}'; }
get_mem_percent(){ free -m | awk '/Mem:/ {printf "%.0f%%",$3/$2*100}'; }
get_disk(){ df -h / | awk 'NR==2 {print $3" / "$2}'; }
get_uptime(){ uptime -p 2>/dev/null | sed 's/up //' || echo unknown; }
get_kernel(){ uname -r; }
count_lines(){ [ -f "$1" ] && wc -l < "$1" || echo 0; }
count_ssh(){ count_lines "$DB"; }
count_vmess(){ count_lines "$XDB/vmess-ws.db"; }
count_vless(){ count_lines "$XDB/vless-ws.db"; }
count_trojan(){ count_lines "$XDB/trojan-ws.db"; }

human_bytes(){
  local B="${1:-0}"
  awk -v b="$B" 'BEGIN{
    if(b>=1073741824) printf "%.2f GB",b/1073741824;
    else if(b>=1048576) printf "%.2f MB",b/1048576;
    else if(b>=1024) printf "%.2f KB",b/1024;
    else printf "%d B",b
  }'
}

human_mb_decimal(){
  local B="${1:-0}"
  awk -v b="$B" 'BEGIN{printf "%.2f MB", b/1000000}'
}

quota_mb_decimal(){
  local Q="$1" N
  case "$Q" in
    ""|0|Unlimited|unlimited|UNLIMITED)
      echo "Unlimited"
      ;;
    *GB|*gb|*Gb|*gB)
      N="${Q%??}"
      [[ "$N" =~ ^[0-9]+$ ]] && awk -v n="$((10#$N))" 'BEGIN{printf "%.0f MB", n*1000}' || echo "Unlimited"
      ;;
    *)
      [[ "$Q" =~ ^[0-9]+$ ]] && awk -v n="$((10#$Q))" 'BEGIN{printf "%.0f MB", n*1000}' || echo "Unlimited"
      ;;
  esac
}

remaining_exact(){
  local EXP="$1" NOW END SEC DAYS HOURS MINS

  case "$EXP" in
    0|Unlimited|unlimited|UNLIMITED|"")
      echo "Unlimited"
      return
      ;;
  esac

  NOW="$(date +%s)"
  END="$(date -d "$EXP 23:59:59" +%s 2>/dev/null || echo 0)"

  if [ "$END" -le 0 ]; then
    echo "Unknown"
    return
  fi

  SEC=$((END - NOW))
  [ "$SEC" -lt 0 ] && SEC=0

  DAYS=$((SEC / 86400))
  HOURS=$(((SEC % 86400) / 3600))
  MINS=$(((SEC % 3600) / 60))

  printf "%d day(s), %d hour(s), %d minute(s)" "$DAYS" "$HOURS" "$MINS"
}

extend_expiry_date(){
  local U="$1" DAYS="$2" INFO EXP NOW_TS BASE_TS EXP_TS
  INFO="$(grep "^$U|" "$DB" 2>/dev/null || true)"
  EXP="$(printf '%s\n' "$INFO" | awk -F'|' '{print $3}')"
  NOW_TS="$(date +%s)"
  EXP_TS="$(date -d "${EXP:-} 23:59:59" +%s 2>/dev/null || echo 0)"
  if [ "$EXP_TS" -gt "$NOW_TS" ]; then
    BASE_TS="$(date -d "$EXP 00:00:00" +%s)"
  else
    BASE_TS="$(date -d "today 00:00:00" +%s)"
  fi
  date -d "@$((BASE_TS + DAYS * 86400))" +%Y-%m-%d
}

quick_user_report(){
  quota_sync

  local INFO U P E Q L USED LIMIT_BYTES REMAIN_BYTES ACTIVE LEFT_LOGINS

  refresh_screen
  select_ssh_user_compact || { pause; return; }

  INFO="$(grep "^$USER|" "$DB" 2>/dev/null || true)"
  [ -n "$INFO" ] || { echo "User not found."; pause; return; }

  IFS='|' read -r U P E Q L <<< "$INFO"
  USED="$(user_used_bytes "$U")"
  USED="${USED:-0}"
  LIMIT_BYTES="$(quota_bytes_from_text "$Q")"
  ACTIVE="$(active_user_logins "$U")"

  if [ "$LIMIT_BYTES" -eq 0 ]; then
    REMAIN_TEXT="Unlimited"
    TOTAL_TEXT="Unlimited"
  else
    if [ "$USED" -ge "$LIMIT_BYTES" ]; then
      REMAIN_BYTES=0
    else
      REMAIN_BYTES=$((LIMIT_BYTES - USED))
    fi
    REMAIN_TEXT="$(human_mb_decimal "$REMAIN_BYTES")"
    TOTAL_TEXT="$(quota_mb_decimal "$Q")"
  fi

  case "$L" in
    Unlimited|unlimited|UNLIMITED|0|"")
      LOGIN_LEFT="Unlimited"
      ;;
    *)
      if [[ "$L" =~ ^[0-9]+$ ]]; then
        LN=$((10#$L))
        [ "$ACTIVE" -ge "$LN" ] && LOGIN_LEFT=0 || LOGIN_LEFT=$((LN-ACTIVE))
      else
        LOGIN_LEFT="Unknown"
      fi
      ;;
  esac

  refresh_screen
  echo "----------------------------------------"
  printf "%-10s %s\n" "$U" "$(human_mb_decimal "$USED")"
  echo "----------------------------------------"
  printf "%-16s : %s\n" "Remaining" "$REMAIN_TEXT"
  printf "%-16s : %s / %s\n" "Traffic" "$(human_mb_decimal "$USED")" "$TOTAL_TEXT"
  echo "----------------------------------------"
  printf "%-16s : %s\n" "Active Logins" "$ACTIVE"
  printf "%-16s : %s\n" "Login Limit" "$L"
  printf "%-16s : %s\n" "Logins Left" "$LOGIN_LEFT"
  echo "----------------------------------------"
  printf "%-16s : %s\n" "Expire Date" "$E"
  printf "%-16s : %s\n" "Time Left" "$(remaining_exact "$E")"
  echo "----------------------------------------"
  pause
}

quota_sync(){ /usr/local/sbin/sultan-quota-sync >/dev/null 2>&1 || true; }

user_used_bytes(){
  awk -F'|' -v u="$1" '$1==u{print $2;exit}' "$USAGE_DB" 2>/dev/null
}

quota_bytes_from_text(){
  local Q="$1" N
  case "$Q" in
    ""|0|Unlimited|unlimited|UNLIMITED) echo 0 ;;
    *GB|*gb|*Gb|*gB)
      N="${Q%??}"
      [[ "$N" =~ ^[0-9]+$ ]] && echo $((10#$N*1024*1024*1024)) || echo 0
      ;;
    *) [[ "$Q" =~ ^[0-9]+$ ]] && echo $((10#$Q*1024*1024*1024)) || echo 0 ;;
  esac
}

remaining_days(){
  local EXP="$1" NOW END DAYS
  case "$EXP" in
    0|Unlimited|unlimited|UNLIMITED|"") echo "Unlimited"; return ;;
  esac
  NOW="$(date +%s)"
  END="$(date -d "$EXP 23:59:59" +%s 2>/dev/null || echo 0)"
  [ "$END" -gt 0 ] || { echo "Unknown"; return; }
  DAYS=$(( (END - NOW + 86399) / 86400 ))
  [ "$DAYS" -lt 0 ] && DAYS=0
  echo "$DAYS days"
}

active_user_logins(){
  local U="$1" DIR="/run/sultan-login-slots/$1" F PID CMD SAVED_START CURRENT_START COUNT=0
  [ -d "$DIR" ] || { echo 0; return; }
  shopt -s nullglob
  for F in "$DIR"/*; do
    PID="${F##*/}"
    if [[ "$PID" =~ ^[0-9]+$ ]] && [ -d "/proc/$PID" ]; then
      CMD="$(cat "/proc/$PID/comm" 2>/dev/null || true)"
      SAVED_START="$(awk -F= '$1=="start"{print $2;exit}' "$F" 2>/dev/null || true)"
      CURRENT_START="$(awk '{print $22}' "/proc/$PID/stat" 2>/dev/null || true)"
      if [ "$CMD" = "sshd" ] && [ -n "$SAVED_START" ] && [ "$SAVED_START" = "$CURRENT_START" ]; then
        COUNT=$((COUNT+1))
        continue
      fi
    fi
    rm -f -- "$F" 2>/dev/null || true
  done
  shopt -u nullglob
  echo "$COUNT"
}

epoch_to_human(){
  local T="${1:-}"
  [[ "$T" =~ ^[0-9]+$ ]] || { echo "Unknown"; return; }
  date -d "@$T" "+%d/%m/%y %H:%M" 2>/dev/null || echo "Unknown"
}

human_duration(){
  local S="${1:-0}" D H M
  [[ "$S" =~ ^[0-9]+$ ]] || S=0
  D=$((S / 86400))
  H=$(((S % 86400) / 3600))
  M=$(((S % 3600) / 60))
  if [ "$D" -gt 0 ]; then
    printf "%d day(s), %d hour(s), %d minute(s)" "$D" "$H" "$M"
  else
    printf "%d hour(s), %d minute(s)" "$H" "$M"
  fi
}

active_device_logins(){
  local U="$1" ID="$2" DIR="/run/sultan-login-slots/$1" F PID CMD SAVED_START CURRENT_START DID COUNT=0
  [ -d "$DIR" ] || { echo 0; return; }
  shopt -s nullglob
  for F in "$DIR"/*; do
    PID="${F##*/}"
    [[ "$PID" =~ ^[0-9]+$ ]] || continue
    [ -d "/proc/$PID" ] || continue
    CMD="$(cat "/proc/$PID/comm" 2>/dev/null || true)"
    SAVED_START="$(awk -F= '$1=="start"{print $2;exit}' "$F" 2>/dev/null || true)"
    CURRENT_START="$(awk '{print $22}' "/proc/$PID/stat" 2>/dev/null || true)"
    [ "$CMD" = "sshd" ] || continue
    [ -n "$SAVED_START" ] && [ "$SAVED_START" = "$CURRENT_START" ] || continue
    DID="$(awk -F= '$1=="device_id"{print $2;exit}' "$F" 2>/dev/null || true)"
    [ "$DID" = "$ID" ] && COUNT=$((COUNT+1))
  done
  shopt -u nullglob
  echo "$COUNT"
}

active_device_seconds(){
  local U="$1" ID="$2" PERIOD_START="${3:-0}" NOW F PID CMD SAVED_START CURRENT_START DID CREATED A B TOTAL=0 DIR="/run/sultan-login-slots/$1"
  NOW="$(date +%s)"
  [ -d "$DIR" ] || { echo 0; return; }
  shopt -s nullglob
  for F in "$DIR"/*; do
    PID="${F##*/}"
    [[ "$PID" =~ ^[0-9]+$ ]] || continue
    [ -d "/proc/$PID" ] || continue
    CMD="$(cat "/proc/$PID/comm" 2>/dev/null || true)"
    SAVED_START="$(awk -F= '$1=="start"{print $2;exit}' "$F" 2>/dev/null || true)"
    CURRENT_START="$(awk '{print $22}' "/proc/$PID/stat" 2>/dev/null || true)"
    [ "$CMD" = "sshd" ] || continue
    [ -n "$SAVED_START" ] && [ "$SAVED_START" = "$CURRENT_START" ] || continue
    DID="$(awk -F= '$1=="device_id"{print $2;exit}' "$F" 2>/dev/null || true)"
    [ "$DID" = "$ID" ] || continue
    CREATED="$(awk -F= '$1=="created"{print $2;exit}' "$F" 2>/dev/null || true)"
    [[ "$CREATED" =~ ^[0-9]+$ ]] || CREATED="$NOW"
    A="$CREATED"
    [ "$A" -lt "$PERIOD_START" ] && A="$PERIOD_START"
    B="$NOW"
    [ "$B" -gt "$A" ] && TOTAL=$((TOTAL + B - A))
  done
  shopt -u nullglob
  echo "$TOTAL"
}

closed_device_seconds(){
  local U="$1" ID="$2" PERIOD_START="${3:-0}" NOW
  NOW="$(date +%s)"
  awk -F'|' -v u="$U" -v id="$ID" -v ps="$PERIOD_START" -v now="$NOW" '
    $1==u && $2==id {
      s=$4+0; e=$5+0;
      if(e<=0){e=now}
      if(e>ps && s<now){
        a=(s>ps?s:ps); b=(e<now?e:now);
        if(b>a){total+=b-a}
      }
    }
    END{print total+0}
  ' "$DEVICE_SESSIONS" 2>/dev/null
}

device_seconds_total(){
  local U="$1" ID="$2" PERIOD_START="${3:-0}" A B
  A="$(closed_device_seconds "$U" "$ID" "$PERIOD_START")"
  B="$(active_device_seconds "$U" "$ID" "$PERIOD_START")"
  [[ "$A" =~ ^[0-9]+$ ]] || A=0
  [[ "$B" =~ ^[0-9]+$ ]] || B=0
  echo $((A+B))
}

device_usage_values(){
  local U="$1" ID="$2" LINE TOTAL DAYKEY DAYBYTES MONTHKEY MONTHBYTES TODAY MONTH
  TODAY="$(date +%F)"
  MONTH="$(date +%Y-%m)"
  LINE="$(awk -F'|' -v u="$U" -v id="$ID" '$1==u && $2==id{print;exit}' "$DEVICE_USAGE_DB" 2>/dev/null || true)"
  TOTAL="$(printf '%s\n' "$LINE" | awk -F'|' '{print $3}')"
  DAYKEY="$(printf '%s\n' "$LINE" | awk -F'|' '{print $4}')"
  DAYBYTES="$(printf '%s\n' "$LINE" | awk -F'|' '{print $5}')"
  MONTHKEY="$(printf '%s\n' "$LINE" | awk -F'|' '{print $6}')"
  MONTHBYTES="$(printf '%s\n' "$LINE" | awk -F'|' '{print $7}')"
  [[ "$TOTAL" =~ ^[0-9]+$ ]] || TOTAL=0
  [[ "$DAYBYTES" =~ ^[0-9]+$ ]] || DAYBYTES=0
  [[ "$MONTHBYTES" =~ ^[0-9]+$ ]] || MONTHBYTES=0
  [ "$DAYKEY" = "$TODAY" ] || DAYBYTES=0
  [ "$MONTHKEY" = "$MONTH" ] || MONTHBYTES=0
  printf '%s|%s|%s\n' "$TOTAL" "$DAYBYTES" "$MONTHBYTES"
}

device_statistics_menu(){
  refresh_screen
  select_ssh_user_compact || { pause; return; }
  quota_sync

  local CHOICE SELECTED LINE DEVICES N=1 U ID NAME IP FIRST LAST HINT
  while true; do
    refresh_screen
    echo "========================================"
    echo "          DEVICE LIST"
    echo "========================================"
    echo ""
    echo "User : $USER"
    echo ""

    DEVICES="$(awk -F'|' -v u="$USER" '$1==u{print}' "$DEVICE_DB" 2>/dev/null || true)"
    if [ -z "$DEVICES" ]; then
      echo "No devices found."
      echo ""
      echo "========================================"
      pause
      return
    fi

    N=1
    printf '%s\n' "$DEVICES" | while IFS='|' read -r U ID NAME IP FIRST LAST HINT; do
      [ -n "$ID" ] || continue
      echo "----------------------------------------"
      printf "(%d) Device Name\n" "$N"
      printf "    %s\n\n" "${NAME:-Unknown Device}"
      echo "    Device ID"
      printf "    %s\n\n" "$ID"
      echo "    IP Address"
      printf "    %s\n\n" "${IP:-Unknown}"
      echo "    Last Login"
      printf "    %s\n" "$(epoch_to_human "$LAST")"
      N=$((N+1))
    done
    echo "----------------------------------------"
    echo ""
    read -p "Select Device: " CHOICE
    [ "$CHOICE" = "0" ] && return

    if [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
      SELECTED="$(printf '%s\n' "$DEVICES" | awk -F'|' -v n="$CHOICE" 'NF && ++i==n {print $2; exit}')"
    else
      SELECTED="$(printf '%s\n' "$DEVICES" | awk -F'|' -v q="$CHOICE" 'tolower($2)==tolower(q) || tolower($3)==tolower(q) {print $2; exit}')"
    fi

    if [ -z "$SELECTED" ]; then
      echo "Device not found."
      pause
      continue
    fi

    show_device_details "$USER" "$SELECTED"
  done
}

show_device_details(){
  local U="$1" ID="$2" LINE NAME IP FIRST LAST HINT USAGE TOTAL TODAY MONTH ONLINE DAY_START MONTH_START SEC_TOTAL SEC_TODAY SEC_MONTH
  quota_sync
  LINE="$(awk -F'|' -v u="$U" -v id="$ID" '$1==u && $2==id{print;exit}' "$DEVICE_DB" 2>/dev/null || true)"
  [ -n "$LINE" ] || { echo "Device not found."; pause; return; }
  NAME="$(printf '%s\n' "$LINE" | awk -F'|' '{print $3}')"
  IP="$(printf '%s\n' "$LINE" | awk -F'|' '{print $4}')"
  FIRST="$(printf '%s\n' "$LINE" | awk -F'|' '{print $5}')"
  LAST="$(printf '%s\n' "$LINE" | awk -F'|' '{print $6}')"
  HINT="$(printf '%s\n' "$LINE" | awk -F'|' '{print $7}')"
  USAGE="$(device_usage_values "$U" "$ID")"
  TOTAL="${USAGE%%|*}"
  TODAY="$(printf '%s\n' "$USAGE" | awk -F'|' '{print $2}')"
  MONTH="$(printf '%s\n' "$USAGE" | awk -F'|' '{print $3}')"
  ONLINE="$(active_device_logins "$U" "$ID")"
  DAY_START="$(date -d "today 00:00:00" +%s 2>/dev/null || echo 0)"
  MONTH_START="$(date -d "$(date +%Y-%m-01) 00:00:00" +%s 2>/dev/null || echo 0)"
  SEC_TOTAL="$(device_seconds_total "$U" "$ID" 0)"
  SEC_TODAY="$(device_seconds_total "$U" "$ID" "$DAY_START")"
  SEC_MONTH="$(device_seconds_total "$U" "$ID" "$MONTH_START")"

  refresh_screen
  echo "========================================"
  echo "        DEVICE STATISTICS"
  echo "========================================"
  printf "%-18s : %s\n" "User" "$U"
  printf "%-18s : %s\n" "Device Name" "${NAME:-Unknown Device}"
  printf "%-18s : %s\n" "Device ID" "$ID"
  printf "%-18s : %s\n" "IP Address" "${IP:-Unknown}"
  if [ "$ONLINE" -gt 0 ]; then
    printf "%-18s : %s\n" "Online Now" "YES"
  else
    printf "%-18s : %s\n" "Online Now" "NO"
  fi
  echo "----------------------------------------"
  printf "%-18s : %s\n" "Traffic Total" "$(human_bytes "$TOTAL")"
  printf "%-18s : %s\n" "Traffic Today" "$(human_bytes "$TODAY")"
  printf "%-18s : %s\n" "Traffic Month" "$(human_bytes "$MONTH")"
  echo "----------------------------------------"
  printf "%-18s : %s\n" "Hours Total" "$(human_duration "$SEC_TOTAL")"
  printf "%-18s : %s\n" "Hours Today" "$(human_duration "$SEC_TODAY")"
  printf "%-18s : %s\n" "Hours Month" "$(human_duration "$SEC_MONTH")"
  echo "----------------------------------------"
  printf "%-18s : %s\n" "First Login" "$(epoch_to_human "$FIRST")"
  printf "%-18s : %s\n" "Last Login" "$(epoch_to_human "$LAST")"
  echo "========================================"
  pause
}

show_user_statistics(){
  quota_sync

  local INFO U P E Q L USED LIMIT REMAIN ACTIVE LEFT_DAYS LOGIN_REMAIN
  INFO="$(grep "^$USER|" "$DB" 2>/dev/null || true)"
  [ -n "$INFO" ] || { echo "User not found."; pause; return; }

  IFS='|' read -r U P E Q L <<< "$INFO"
  USED="$(user_used_bytes "$U")"
  USED="${USED:-0}"
  LIMIT="$(quota_bytes_from_text "$Q")"
  ACTIVE="$(active_user_logins "$U")"
  LEFT_DAYS="$(remaining_days "$E")"

  if [ "$LIMIT" -eq 0 ]; then
    REMAIN="Unlimited"
  elif [ "$USED" -ge "$LIMIT" ]; then
    REMAIN="0 B"
  else
    REMAIN="$(human_bytes $((LIMIT-USED)))"
  fi

  case "$L" in
    Unlimited|unlimited|UNLIMITED|0|"") LOGIN_REMAIN="Unlimited" ;;
    *)
      if [[ "$L" =~ ^[0-9]+$ ]]; then
        LN=$((10#$L))
        [ "$ACTIVE" -ge "$LN" ] && LOGIN_REMAIN="0" || LOGIN_REMAIN=$((LN-ACTIVE))
      else
        LOGIN_REMAIN="Unknown"
      fi
      ;;
  esac

  refresh_screen
  echo -e "${ORANGE}========================================${NC}"
  echo -e "${ORANGE}            USER STATISTICS${NC}"
  echo -e "${ORANGE}========================================${NC}"
  printf "%-16s : %s\n" "Username" "$U"
  printf "%-16s : %s\n" "Used Traffic" "$(human_bytes "$USED")"
  printf "%-16s : %s\n" "Traffic Limit" "$Q"
  printf "%-16s : %s\n" "Traffic Left" "$REMAIN"
  echo "----------------------------------------"
  printf "%-16s : %s\n" "Active Logins" "$ACTIVE"
  printf "%-16s : %s\n" "Login Limit" "$L"
  printf "%-16s : %s\n" "Logins Left" "$LOGIN_REMAIN"
  echo "----------------------------------------"
  printf "%-16s : %s\n" "Expire Date" "$E"
  printf "%-16s : %s\n" "Days Left" "$LEFT_DAYS"
  echo -e "${ORANGE}========================================${NC}"
  pause
}


is_system_ssh_user(){
  id "$1" >/dev/null 2>&1 || return 1
  local S
  S="$(awk -F: -v u="$1" '$1==u{print $7}' /etc/passwd)"
  [ "$S" != "/usr/sbin/nologin" ] && [ "$S" != "/bin/false" ]
}

get_user_db_line(){
  grep "^$1|" "$DB" 2>/dev/null | head -n1
}

show_ssh_users_table(){
  quota_sync
  echo "================================================================================"
  printf "%-4s %-15s %-12s %-14s %-10s %-10s %-12s\n" \
    "NO" "USERNAME" "PASSWORD" "EXPIRE" "QUOTA" "LOGIN" "USED"
  echo "================================================================================"

  local N=1
  while IFS='|' read -r U P E Q L; do
    [ -n "$U" ] || continue
    id "$U" >/dev/null 2>&1 || continue
    B="$(user_used_bytes "$U")"
    B="${B:-0}"
    printf "%-4s %-15s %-12s %-14s %-10s %-10s %-12s\n" \
      "$N" "$U" "$P" "$E" "$Q" "$L" "$(human_bytes "$B")"
    N=$((N+1))
  done < "$DB"

  echo "================================================================================"
}

select_ssh_user(){
  local PROMPT="${1:-Select user}"
  local CHOICE SELECTED

  if [ ! -s "$DB" ]; then
    echo "No SSH users found."
    return 1
  fi

  show_ssh_users_table
  read -p "$PROMPT (number or username, 0 = cancel): " CHOICE

  [ "$CHOICE" = "0" ] && return 1

  if [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
    SELECTED="$(awk -F'|' -v n="$CHOICE" 'NF && ++i==n {print $1; exit}' "$DB")"
  else
    SELECTED="$CHOICE"
  fi

  if ! grep -q "^${SELECTED}|" "$DB" 2>/dev/null || ! id "$SELECTED" >/dev/null 2>&1; then
    echo "User not found."
    return 1
  fi

  USER="$SELECTED"
  return 0
}

show_ssh_users_compact(){
  quota_sync
  echo "========================================"
  echo "              SSH USERS"
  echo "========================================"
  echo ""

  local N=1 U
  while IFS='|' read -r U _ _ _ _; do
    [ -n "$U" ] || continue
    id "$U" >/dev/null 2>&1 || continue
    printf "(%d) %s\n" "$N" "$U"
    N=$((N+1))
  done < "$DB"

  echo ""
  echo "========================================"
}

select_ssh_user_compact(){
  local CHOICE SELECTED

  show_ssh_users_compact
  read -p "Select User: " CHOICE

  [ "$CHOICE" = "0" ] && return 1

  if [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
    SELECTED="$(awk -F'|' -v n="$CHOICE" 'NF && ++i==n {print $1; exit}' "$DB")"
  else
    SELECTED="$CHOICE"
  fi

  if ! grep -q "^${SELECTED}|" "$DB" 2>/dev/null || ! id "$SELECTED" >/dev/null 2>&1; then
    echo "User not found."
    return 1
  fi

  USER="$SELECTED"
  return 0
}

show_selected_user_details(){
  local INFO USED
  INFO="$(grep "^$USER|" "$DB" 2>/dev/null || true)"

  if [ -n "$INFO" ]; then
    IFS='|' read -r U P E Q L <<< "$INFO"
  else
    U="$USER"
    P="Unknown"
    E="$(chage -l "$USER" 2>/dev/null | awk -F: '/Account expires/{print $2}' | xargs)"
    [ -n "$E" ] || E="Unknown"
    Q="Unknown"
    L="Unlimited"
  fi

  USED="$(user_used_bytes "$U")"
  USED="${USED:-0}"

  echo ""
  echo "========================================"
  printf "%-10s : %s\n" "Username" "$U"
  printf "%-10s : %s\n" "Password" "${P:-Unknown}"
  printf "%-10s : %s\n" "Expire" "$E"
  printf "%-10s : %s\n" "Quota" "$Q"
  printf "%-10s : %s\n" "Used" "$(human_bytes "$USED")"
  printf "%-10s : %s\n" "Login" "$L"
  echo "========================================"
}

change_selected_user_quota(){
  local INFO U P E Q L USED
  quota_sync
  INFO="$(grep "^$USER|" "$DB" 2>/dev/null || true)"
  IFS='|' read -r U P E Q L <<< "$INFO"
  USED="$(user_used_bytes "$U")"
  USED="${USED:-0}"

  refresh_screen
  echo "========================================"
  echo "            CHANGE USER QUOTA"
  echo "========================================"
  printf "%-12s : %s\n" "Username" "$U"
  printf "%-12s : %s\n" "Current Quota" "$Q"
  printf "%-12s : %s\n" "Used Traffic" "$(human_bytes "$USED")"
  echo "----------------------------------------"
  echo "0 = Unlimited"
  echo "Traffic already used will not reset."
  echo "========================================"
  read -p "New GB Limit: " GB

  [[ "$GB" =~ ^[0-9]+$ ]] || { echo "Invalid value."; pause; return; }
  GB=$((10#$GB))
  [ "$GB" = "0" ] && GB_TEXT="0" || GB_TEXT="${GB}GB"

  db_update_field "$USER" 4 "$GB_TEXT" || { echo "Update failed."; pause; return; }

  quota_sync
  echo ""
  echo "Quota changed to: $GB_TEXT"
  pause
}

change_selected_user_login(){
  local INFO U P E Q L
  INFO="$(grep "^$USER|" "$DB" 2>/dev/null || true)"
  IFS='|' read -r U P E Q L <<< "$INFO"

  refresh_screen
  echo "========================================"
  echo "          CHANGE LOGIN LIMIT"
  echo "========================================"
  printf "%-14s : %s\n" "Username" "$U"
  printf "%-14s : %s\n" "Current Limit" "$L"
  echo "----------------------------------------"
  echo "0 = Unlimited"
  echo "1 = One active login"
  echo "2 = Two active logins"
  echo "========================================"
  read -p "Change login limit (0 = Unlimited): " MAXLOGIN

  [[ "$MAXLOGIN" =~ ^[0-9]+$ ]] || { echo "Invalid value."; pause; return; }
  MAXLOGIN=$((10#$MAXLOGIN))
  [ "$MAXLOGIN" = "0" ] && LOGIN_TEXT="0" || LOGIN_TEXT="$MAXLOGIN"

  db_update_field "$USER" 5 "$LOGIN_TEXT" || { echo "Update failed."; pause; return; }

  echo ""
  echo "Login limit changed to: $LOGIN_TEXT"
  pause
}

change_selected_user_password(){
  refresh_screen
  echo "========================================"
  echo "           CHANGE PASSWORD"
  echo "========================================"
  printf "%-10s : %s\n" "Username" "$USER"
  echo "========================================"
  read -r -s -p "New Password: " PASS
  echo ""

  validate_password "$PASS" || { echo "Invalid password."; pause; return; }
  printf '%s:%s
' "$USER" "$PASS" | chpasswd || { echo "Password change failed."; pause; return; }
  db_update_field "$USER" 2 "$PASS" || { echo "Password save failed."; pause; return; }

  echo "Password changed."
  pause
}

extend_selected_user(){
  refresh_screen
  echo "========================================"
  echo "             EXTEND USER"
  echo "========================================"
  printf "%-10s : %s\n" "Username" "$USER"
  echo "0 = Unlimited"
  echo "========================================"
  read -p "Add Days: " DAYS

  [[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "Invalid value."; pause; return; }
  DAYS=$((10#$DAYS))

  if [ "$DAYS" = "0" ]; then
    chage -d -1 -E -1 -I -1 -m 0 -M 99999 "$USER"
    EXP="0"
  else
    EXP="$(extend_expiry_date "$USER" "$DAYS")"
    chage -E "$EXP" "$USER"
  fi

  db_update_field "$USER" 3 "$EXP" || { echo "Update failed."; pause; return; }

  echo "New Expire: $EXP"
  pause
}

reset_selected_user_traffic(){
  refresh_screen
  echo "========================================"
  echo "          RESET USER TRAFFIC"
  echo "========================================"
  printf "%-10s : %s\n" "Username" "$USER"
  echo "This resets the saved traffic counter."
  echo "========================================"
  read -p "Type YES to reset: " CONFIRM

  [ "$CONFIRM" = "YES" ] || { echo "Cancelled."; pause; return; }

  usage_reset_user "$USER" || { echo "Traffic reset failed."; pause; return; }
  quota_sync
  echo "Traffic reset."
  pause
}

delete_selected_user(){
  refresh_screen
  echo "========================================"
  echo "             DELETE USER"
  echo "========================================"
  show_selected_user_details
  read -p "Type YES to delete: " CONFIRM

  [ "$CONFIRM" = "YES" ] || { echo "Cancelled."; pause; return; }

  delete_managed_ssh_user "$USER" || { pause; return; }
  echo "User deleted."
  pause
}

delete_ssh_user_direct(){
  refresh_screen
  select_ssh_user_compact || { pause; return; }

  refresh_screen
  echo "========================================"
  echo "             DELETE USER"
  echo "========================================"
  show_selected_user_details
  echo ""
  echo "(1) Delete User"
  echo "(0) Cancel"
  echo "========================================"
  read -p "Select: " CONFIRM

  [ "$CONFIRM" = "1" ] || { echo "Cancelled."; pause; return; }

  delete_managed_ssh_user "$USER" || { pause; return; }

  echo ""
  echo "User deleted successfully: $USER"
  pause
}

change_ssh_user_menu(){
  refresh_screen
  select_ssh_user_compact || { pause; return; }

  while true; do
    quota_sync
    refresh_screen
    show_selected_user_details
    echo ""
    echo "(1) Change Traffic Limit"
    echo "(2) Change Login Limit"
    echo "(3) Change Password"
    echo "(4) Change Expire"
    echo "(5) Delete User"
    echo "(6) Show Statistics"
    echo "(0) Back"
    echo ""
    read -p "Choose: " ACTION

    case "$ACTION" in
      1) change_selected_user_quota ;;
      2) change_selected_user_login ;;
      3) change_selected_user_password ;;
      4) extend_selected_user ;;
      5) delete_selected_user; return ;;
      6) show_user_statistics ;;
      0) return ;;
    esac
  done
}

xray_db_update_field(){
  local DBF="$1" U="$2" FIELD="$3" VALUE="$4" TMP LOCKF
  LOCKF="${DBF}.lock"
  (
    flock -x 7
    TMP="$(mktemp "$XDB/.xraydb.XXXXXX")" || exit 1
    awk -F'|' -v u="$U" -v f="$FIELD" -v v="$VALUE" '
      BEGIN{OFS="|"; found=0}
      $1==u{$f=v; found=1}
      {print}
      END{if(!found) exit 2}
    ' "$DBF" > "$TMP" || { rm -f "$TMP"; exit 1; }
    chmod 600 "$TMP"
    mv -f "$TMP" "$DBF"
  ) 7>"$LOCKF"
}

xray_path_encoded(){
  local P="$1"
  printf '%s' "${P//\//%2F}"
}

xray_user_used_bytes(){
  local U="$1" OUT USED
  OUT="$(xray api statsquery --server=127.0.0.1:10090 -pattern "user>>>$U>>>traffic>>>" 2>/dev/null || true)"
  USED="$(printf '%s\n' "$OUT" | awk -F"value:" '
    NF > 1 {
      v=$2;
      gsub(/[^0-9]/, "", v);
      if(v!="") sum += v
    }
    END{print sum+0}
  ')"
  [[ "$USED" =~ ^[0-9]+$ ]] || USED=0
  echo "$USED"
}

xray_link(){
  local PROTO="$1" U="$2" VALUE="$3" LINK_ADDR="$4" PATHX="$5" CLIENT_HOST="${6:-}" CLIENT_SNI="${7:-}" ALLOW_INSECURE="${8:-0}" PENC JSON B64 AI_PARAM
  PENC="$(xray_path_encoded "$PATHX")"
  validate_link_address "$LINK_ADDR" || LINK_ADDR="$CLIENT_HOST"
  validate_domain "$CLIENT_HOST" || CLIENT_HOST="$LINK_ADDR"
  validate_domain "$CLIENT_SNI" || CLIENT_SNI="$CLIENT_HOST"
  case "$ALLOW_INSECURE" in
    1|y|Y|yes|YES|true|TRUE|on|ON) ALLOW_INSECURE=1 ;;
    *) ALLOW_INSECURE=0 ;;
  esac
  [ "$ALLOW_INSECURE" = "1" ] && AI_PARAM="&allowInsecure=1" || AI_PARAM=""
  case "$PROTO" in
    vless)
      printf 'vless://%s@%s:443?encryption=none&security=tls&type=ws&host=%s&sni=%s&path=%s%s#%s\n' \
        "$VALUE" "$LINK_ADDR" "$CLIENT_HOST" "$CLIENT_SNI" "$PENC" "$AI_PARAM" "$U"
      ;;
    trojan)
      printf 'trojan://%s@%s:443?security=tls&type=ws&host=%s&sni=%s&path=%s%s#%s\n' \
        "$VALUE" "$LINK_ADDR" "$CLIENT_HOST" "$CLIENT_SNI" "$PENC" "$AI_PARAM" "$U"
      ;;
    *)
      JSON="$(printf '{"v":"2","ps":"%s","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"%s","tls":"tls","sni":"%s","allowInsecure":"%s"}' \
        "$U" "$LINK_ADDR" "$VALUE" "$CLIENT_HOST" "$PATHX" "$CLIENT_SNI" "$ALLOW_INSECURE")"
      B64="$(printf '%s' "$JSON" | base64 | tr -d '\n')"
      printf 'vmess://%s\n' "$B64"
      ;;
  esac
}

show_xray_users_table(){
  local DBF="$1" TITLE="$2" N=1 U V PROTO NET DOMAIN PATHX EXP QUOTA LOGIN CREATED USED
  echo "================================================================================"
  printf "%-4s %-15s %-14s %-10s %-10s %-12s\n" \
    "NO" "USERNAME" "EXPIRE" "QUOTA" "LOGIN" "USED"
  echo "================================================================================"

  while IFS='|' read -r U V PROTO NET DOMAIN PATHX EXP QUOTA LOGIN CREATED REST; do
    [ -n "$U" ] || continue
    [ -n "$EXP" ] || EXP="0"
    [ -n "$QUOTA" ] || QUOTA="Unlimited"
    [ -n "$LOGIN" ] || LOGIN="Unlimited"
    USED="$(xray_user_used_bytes "$U")"
    printf "%-4s %-15s %-14s %-10s %-10s %-12s\n" \
      "$N" "$U" "$EXP" "$QUOTA" "$LOGIN" "$(human_bytes "$USED")"
    N=$((N+1))
  done < "$DBF"

  echo "================================================================================"
}

select_xray_user(){
  local DBF="$1"
  local TITLE="$2"
  local CHOICE SELECTED

  if [ ! -s "$DBF" ]; then
    echo "No $TITLE users found."
    return 1
  fi

  show_xray_users_table "$DBF" "$TITLE"
  read -p "Select user (number or username, 0 = cancel): " CHOICE
  [ "$CHOICE" = "0" ] && return 1

  if [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
    SELECTED="$(awk -F'|' -v n="$CHOICE" 'NF && ++i==n {print $1; exit}' "$DBF")"
  else
    SELECTED="$CHOICE"
  fi

  if ! grep -q "^${SELECTED}|" "$DBF" 2>/dev/null; then
    echo "User not found."
    return 1
  fi

  USER="$SELECTED"
  return 0
}

stats_small(){
  echo "-----------------------------------"
  box "Total SSH Users" "$(count_ssh)"
  box "Total VMESS Users" "$(count_vmess)"
  box "Total VLESS Users" "$(count_vless)"
  box "Total TROJAN Users" "$(count_trojan)"
  box "Online Users" "$(total_online_logins)"
  echo "-----------------------------------"
}

tls_status(){
  local D="$(get_domain)"
  [ -f "/etc/letsencrypt/live/$D/fullchain.pem" ] && echo ACTIVE || echo OFFLINE
}

bbr_status(){
  sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr &&
    echo ACTIVE || echo OFFLINE
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
  echo -e "${MAG}║${CYAN}                  CROWN CORE v1.3                 ${MAG}║${NC}"
  echo -e "${MAG}║${GREEN}          SSL | V2RAY WS | USER LIMITS          ${MAG}║${NC}"
  echo -e "${MAG}╚════════════════════════════════════════════════════╝${NC}"
  echo -e " ${WHITE}Domain${NC}       : ${CYAN}${DOMAIN}${NC}"
  echo -e " ${WHITE}Server IP${NC}    : ${CYAN}${IP}${NC}"
  echo -e " ${WHITE}Uptime${NC}       : ${GREEN}${UPTIME}${NC}"
  echo -e " ${WHITE}Memory${NC}       : ${GREEN}${MEM}${NC}        ${WHITE}Load${NC}: ${GREEN}${LOAD}${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e " ${WHITE}TLS / SSL${NC}     : $(badge "$(tls_status)")"
  echo -e " ${WHITE}WebSocket${NC}     : $(svc_badge sultan-ws)"
  echo -e " ${WHITE}Xray${NC}          : $(svc_badge xray)"
  echo -e " ${WHITE}UDP Custom${NC}    : $(svc_badge udp-custom)"
  echo -e " ${WHITE}Nginx${NC}         : $(svc_badge nginx)"
  echo -e " ${WHITE}HAProxy${NC}       : $(svc_badge haproxy)"
  echo -e " ${WHITE}SSH${NC}           : $(svc_badge ssh)"
  echo -e " ${WHITE}Fail2Ban${NC}      : $(svc_badge fail2ban)"
  echo -e " ${WHITE}Quota Engine${NC}  : $(svc_badge sultan-quota.timer)"
  echo -e " ${WHITE}BBR${NC}           : $(badge "$(bbr_status)")"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e " ${CYAN}[1]${NC} SSH MENU              ${CYAN}[11]${NC} REBOOT VPS"
  echo -e " ${CYAN}[2]${NC} VMESS LINK MENU       ${CYAN}[12]${NC} ABOUT SCRIPT"
  echo -e " ${CYAN}[3]${NC} VLESS MENU            ${CYAN}[13]${NC} VPS INFO"
  echo -e " ${CYAN}[4]${NC} TROJAN MENU           ${CYAN}[14]${NC} ONLINE USERS"
  echo -e " ${CYAN}[5]${NC} SSR MENU              ${CYAN}[15]${NC} SPEEDTEST"
  echo -e " ${CYAN}[6]${NC} UDP CUSTOM            ${CYAN}[16]${NC} DOMAIN MENU"
  echo -e " ${CYAN}[7]${NC} BOT TELEGRAM          ${CYAN}[17]${NC} SSL MENU"
  echo -e " ${CYAN}[8]${NC} UPDATE SCRIPT         ${CYAN}[18]${NC} XRAY MENU"
  echo -e " ${CYAN}[9]${NC} BACKUP RESTORE        ${CYAN}[19]${NC} FAIL2BAN MENU"
  echo -e " ${CYAN}[10]${NC} SETTING               ${CYAN}[20]${NC} BBR MENU"
  echo ""
  echo -e " ${RED}[99]${NC} REMOVE SCRIPT"
  echo -e " ${YELLOW}[X]${NC} EXIT"
  read -p "👉 Select: " opt

  case "$opt" in
    1) ssh_menu ;;
    2) vmess_menu ;;
    3) vless_menu ;;
    4) trojan_menu ;;
    5) refresh_screen; echo "SSR core is not installed."; pause ;;
    6) udp_menu ;;
    7) bot_menu ;;
    8) refresh_screen; echo "Local full installer build."; pause ;;
    9) backup_menu ;;
    10) setting_menu ;;
    11) reboot ;;
    12) about_menu ;;
    13) vps_info ;;
    14) online_users_menu ;;
    15) refresh_screen; speedtest-cli || true; pause ;;
    16) domain_menu ;;
    17) ssl_menu ;;
    18) xray_menu ;;
    19) fail2ban_menu ;;
    20) bbr_menu ;;
    99) remove_script ;;
    x|X) exit ;;
  esac
done
}

ssh_menu(){
while true; do
  refresh_screen
  echo "========================================"
  echo "               SSH MENU"
  echo "========================================"
  echo "(1) Create SSH User"
  echo "(2) Change SSH User"
  echo "(3) Delete SSH User"
  echo "(4) Online Users"
  echo "(5) Quick User Report"
  echo "(6) User Traffic Statistics"
  echo "(0) Back"
  echo "========================================"
  read -p "Select: " s

  case "$s" in
    1) create_ssh_user ;;
    2) change_ssh_user_menu ;;
    3) delete_ssh_user_direct ;;
    4) online_users_menu ;;
    5) quick_user_report ;;
    6) ssh_user_statistics_menu ;;
    0) return ;;
  esac
done
}

create_ssh_user(){
  refresh_screen
  echo "==================================="
  echo "        CREATE SSH USER"
  echo "==================================="
  show_ssh_users_table
  read -p "Username: " USER
  read -r -s -p "Password: " PASS
  echo ""
  read -p "Days (0 = Unlimited): " DAYS
  read -p "GB Limit (0 = Unlimited): " GB
  read -p "Users/Login Limit (0 = Unlimited): " MAXLOGIN

  validate_username "$USER" || { echo "Invalid username"; pause; return; }
  validate_password "$PASS" || { echo "Invalid password"; pause; return; }
  [[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "Invalid days value"; pause; return; }
  [[ "$GB" =~ ^[0-9]+$ ]] || { echo "Invalid GB value"; pause; return; }
  [[ "$MAXLOGIN" =~ ^[0-9]+$ ]] || { echo "Invalid login value"; pause; return; }
  DAYS=$((10#$DAYS))
  GB=$((10#$GB))
  MAXLOGIN=$((10#$MAXLOGIN))
  [ "$DAYS" -le 36500 ] || { echo "Invalid days value"; pause; return; }
  [ "$GB" -le 1000000 ] || { echo "Invalid GB value"; pause; return; }
  [ "$MAXLOGIN" -le 1000 ] || { echo "Invalid login value"; pause; return; }

  id "$USER" &>/dev/null && { echo "User already exists"; pause; return; }
  grep -q "^${USER}|" "$DB" 2>/dev/null && { echo "User already exists"; pause; return; }

  # Same login method as the old working scripts: normal /bin/bash user.
  # The plaintext password is kept in users.db because the requested legacy panel
  # displays it. /etc/sultan remains root-only (0700/0600).
  useradd -m -s /bin/bash "$USER" || { echo "Failed to create user"; pause; return; }
  printf '%s:%s
' "$USER" "$PASS" | chpasswd || {
    userdel -r "$USER" 2>/dev/null || true
    echo "Failed to set password"
    pause
    return
  }

  if [ "$DAYS" = "0" ]; then
    chage -d -1 -E -1 -I -1 -m 0 -M 99999 "$USER"
    EXP="0"
  else
    EXP="$(extend_expiry_date "$USER" "$DAYS")"
    chage -E "$EXP" "$USER"
  fi

  [ "$GB" = "0" ] && GB_TEXT="0" || GB_TEXT="${GB}GB"
  [ "$MAXLOGIN" = "0" ] && LOGIN_TEXT="0" || LOGIN_TEXT="$MAXLOGIN"

  db_remove_user "$USER" 2>/dev/null || true
  db_add_user "$USER|$PASS|$EXP|$GB_TEXT|$LOGIN_TEXT" || {
    userdel -r "$USER" 2>/dev/null || true
    echo "Failed to save user"
    pause
    return
  }

  quota_sync

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
  show_ssh_users_compact
  pause
}

delete_ssh_user(){
  refresh_screen
  select_ssh_user "Delete user" || { pause; return; }

  echo ""
  read -p "Type YES to delete $USER: " CONFIRM
  [ "$CONFIRM" = "YES" ] || { echo "Cancelled"; pause; return; }

  delete_managed_ssh_user "$USER" || { pause; return; }
  echo "Deleted: $USER"
  pause
}

extend_ssh_user(){
  refresh_screen
  select_ssh_user "Extend user" || { pause; return; }
  read -p "Add days (0 = Unlimited): " DAYS
  [[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "Invalid value"; pause; return; }
  DAYS=$((10#$DAYS))

  if [ "$DAYS" = "0" ]; then
    chage -d -1 -E -1 -I -1 -m 0 -M 99999 "$USER"
    EXP="0"
  else
    EXP="$(extend_expiry_date "$USER" "$DAYS")"
    chage -E "$EXP" "$USER"
  fi

  db_update_field "$USER" 3 "$EXP" || { echo "Update failed."; pause; return; }

  echo "Extended $USER until $EXP"
  pause
}

ssh_user_info(){
  refresh_screen
  select_ssh_user "Show user information" || { pause; return; }
  INFO="$(grep "^$USER|" "$DB" 2>/dev/null || true)"

  IFS='|' read -r U P E Q L <<< "$INFO"
  USED="$(user_used_bytes "$U")"
  USED="${USED:-0}"
  box "Username" "$U"
  box "Password" "$P"
  box "Expire Date" "$E"
  box "Quota" "$Q"
  box "Used" "$(human_bytes "$USED")"
  box "Login Limit" "$L"
  pause
}

ssh_user_statistics_menu(){
  refresh_screen
  select_ssh_user_compact || { pause; return; }

  while true; do
    refresh_screen
    show_selected_user_details
    echo ""
    echo -e "${ORANGE}(1) View Full Statistics${NC}"
    echo "(0) Back"
    echo ""
    read -p "Select: " S

    case "$S" in
      1) show_user_statistics ;;
      0) return ;;
    esac
  done
}

ssh_user_traffic(){
  refresh_screen
  show_ssh_users_table
  pause
}

change_ssh_password(){
  refresh_screen
  select_ssh_user "Change password" || { pause; return; }
  read -r -s -p "New Password for $USER: " PASS
  echo ""
  validate_password "$PASS" || { echo "Invalid password"; pause; return; }
  printf '%s:%s
' "$USER" "$PASS" | chpasswd || { echo "Password change failed"; pause; return; }
  db_update_field "$USER" 2 "$PASS" || { echo "Password save failed"; pause; return; }

  echo "Password changed for $USER"
  pause
}

change_ssh_quota(){
  refresh_screen
  select_ssh_user "Change quota" || { pause; return; }
  read -p "New GB Limit for $USER (0 = Unlimited): " GB
  [[ "$GB" =~ ^[0-9]+$ ]] || { echo "Invalid value"; pause; return; }
  GB=$((10#$GB))

  [ "$GB" = "0" ] && GB_TEXT="0" || GB_TEXT="${GB}GB"

  db_update_field "$USER" 4 "$GB_TEXT" || { echo "Update failed."; pause; return; }

  quota_sync
  echo "Quota changed for $USER to $GB_TEXT"
  pause
}

change_ssh_login(){
  refresh_screen
  select_ssh_user "Change login limit" || { pause; return; }
  read -p "Change login limit (0 = Unlimited): " MAXLOGIN
  [[ "$MAXLOGIN" =~ ^[0-9]+$ ]] || { echo "Invalid value"; pause; return; }
  MAXLOGIN=$((10#$MAXLOGIN))

  [ "$MAXLOGIN" = "0" ] && LOGIN_TEXT="0" || LOGIN_TEXT="$MAXLOGIN"

  db_update_field "$USER" 5 "$LOGIN_TEXT" || { echo "Update failed."; pause; return; }

  echo "Login limit changed for $USER to $LOGIN_TEXT"
  pause
}

xray_prepare_storage(){
  mkdir -p /usr/local/etc/xray "$XDB"
  chmod 700 /usr/local/etc/xray "$XDB" 2>/dev/null || true
  touch "$XDB/vmess-ws.db" "$XDB/vless-ws.db" "$XDB/trojan-ws.db"
  chmod 600 "$XDB"/*.db 2>/dev/null || true
}

xray_binary(){
  local B
  for B in /usr/local/bin/xray /usr/bin/xray /opt/xray/xray; do
    if [ -x "$B" ]; then
      printf '%s\n' "$B"
      return 0
    fi
  done
  command -v xray 2>/dev/null || return 1
}

xray_version_text(){
  local BIN
  BIN="$(xray_binary 2>/dev/null || true)"
  [ -n "$BIN" ] || { echo "missing"; return; }
  "$BIN" version 2>/dev/null | head -n1 || "$BIN" -version 2>/dev/null | head -n1 || echo "unknown"
}

xray_fix_service_access(){
  # The official installer may run Xray as nobody while this panel protects
  # config.json with root-only permissions. That combination makes the unit
  # fail even though a root-level config test succeeds. Use a deterministic
  # service override and keep all public listeners on loopback/high ports.
  mkdir -p /etc/systemd/system/xray.service.d /usr/local/etc/xray
  cat >/etc/systemd/system/xray.service.d/10-sultan-access.conf <<'EOF'
[Service]
User=root
Group=root
EOF
  chown root:root /usr/local/etc/xray
  chmod 755 /usr/local/etc/xray
  if [ -f "$XRAY_CONFIG" ]; then
    chown root:root "$XRAY_CONFIG"
    chmod 600 "$XRAY_CONFIG"
  fi
  systemctl daemon-reload
}

xray_test_file(){
  local FILE="$1" BIN LOG TEST_FILE COPY_FILE=""
  XRAY_TEST_ERROR=""
  BIN="$(xray_binary 2>/dev/null || true)"
  if [ -z "$BIN" ]; then
    XRAY_TEST_ERROR="Xray binary is missing."
    return 1
  fi

  # Xray 26.x detects the config format from the filename extension. Temporary
  # files such as .config.ABC123 have no extension and are rejected before JSON
  # parsing with: Failed to get format. Always test through a .json filename.
  TEST_FILE="$FILE"
  case "$TEST_FILE" in
    *.json) ;;
    *)
      COPY_FILE="$(mktemp --suffix=.json "$BASE/.xray-format.XXXXXX")" || return 1
      cp -f "$FILE" "$COPY_FILE" || { rm -f "$COPY_FILE"; return 1; }
      TEST_FILE="$COPY_FILE"
      ;;
  esac

  LOG="$(mktemp "$BASE/.xray-test.XXXXXX")" || { rm -f "$COPY_FILE"; return 1; }

  if "$BIN" run -test -config "$TEST_FILE" >"$LOG" 2>&1 ||
     "$BIN" run -test -c "$TEST_FILE" >"$LOG" 2>&1 ||
     "$BIN" test -config "$TEST_FILE" >"$LOG" 2>&1 ||
     "$BIN" -test -config "$TEST_FILE" >"$LOG" 2>&1; then
    rm -f "$LOG" "$COPY_FILE"
    return 0
  fi

  XRAY_TEST_ERROR="$(tail -n 20 "$LOG" 2>/dev/null || true)"
  rm -f "$LOG" "$COPY_FILE"
  return 1
}

xray_config_ok(){
  [ -f "$XRAY_CONFIG" ] || return 1
  xray_test_file "$XRAY_CONFIG"
}

xray_restart_safe(){
  local I
  xray_fix_service_access
  if ! xray_config_ok; then
    echo "Xray config error. Restart skipped."
    [ -n "${XRAY_TEST_ERROR:-}" ] && printf '%s\n' "$XRAY_TEST_ERROR"
    return 1
  fi
  systemctl reset-failed xray >/dev/null 2>&1 || true
  if ! systemctl restart xray; then
    echo "Xray service failed to restart."
    systemctl status xray --no-pager -l 2>/dev/null || true
    journalctl -u xray -n 30 --no-pager 2>/dev/null || true
    return 1
  fi
  for I in {1..10}; do
    systemctl is-active --quiet xray 2>/dev/null && return 0
    sleep 1
  done
  echo "Xray stopped after restart."
  systemctl status xray --no-pager -l 2>/dev/null || true
  journalctl -u xray -n 30 --no-pager 2>/dev/null || true
  return 1
}

nginx_haproxy_restart_safe(){
  nginx -t || return 1
  haproxy -c -f /etc/haproxy/haproxy.cfg || return 1
  systemctl enable nginx haproxy >/dev/null 2>&1 || true

  # Old working login method often enters through HAProxy/Nginx -> SSH WebSocket.
  # Reloading either proxy during that session can drop the management SSH tab.
  # When we detect localhost as SSH peer, only write and test configs now, then
  # defer proxy reload until this SSH session has closed.
  if current_session_via_ws; then
    defer_command_until_logout "proxy-reload" "nginx -t && systemctl reload nginx; haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl reload haproxy" || true
    echo "Current SSH session uses WebSocket; Nginx/HAProxy reload was skipped now and deferred until logout."
    return 0
  fi

  if systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl reload nginx || return 1
  else
    checked_restart nginx || return 1
  fi

  if systemctl is-active --quiet haproxy 2>/dev/null; then
    systemctl reload haproxy || checked_restart haproxy || return 1
  else
    checked_restart haproxy || return 1
  fi
}

xray_jq_update(){
  local FILTER="$1" TMP
  shift
  TMP="$(mktemp --suffix=.json "/usr/local/etc/xray/.config.XXXXXX")" || return 1
  jq "$@" "$FILTER" "$XRAY_CONFIG" > "$TMP" || { rm -f "$TMP"; return 1; }
  chmod 600 "$TMP"
  xray_test_file "$TMP" || { rm -f "$TMP"; return 1; }
  mv -f "$TMP" "$XRAY_CONFIG"
}

install_xray(){
  local QUIET="${1:-}" TMP BIN
  [ "$QUIET" = "--quiet" ] || refresh_screen
  TMP="$(mktemp "$BASE/.xray-install.XXXXXX")" || { echo "Cannot create temp file."; [ "$QUIET" = "--quiet" ] || pause; return 1; }
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 20 \
    https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o "$TMP" ||
    { rm -f "$TMP"; echo "Failed to download Xray installer."; [ "$QUIET" = "--quiet" ] || pause; return 1; }
  sed -i 's/red=$(tput setaf 1)/red=$(tput setaf 2)/g' "$TMP"

  # Always install the systemd unit as root. The official installer defaults
  # to nobody on a fresh installation; that can make a protected config.json
  # unreadable and leave the service OFFLINE.
  if ! bash "$TMP" install --force -u root; then
    rm -f "$TMP"
    echo "Xray install failed."
    [ "$QUIET" = "--quiet" ] || pause
    return 1
  fi
  rm -f "$TMP"
  hash -r 2>/dev/null || true
  BIN="$(xray_binary 2>/dev/null || true)"
  [ -n "$BIN" ] && [ -x "$BIN" ] || { echo "Xray binary was not installed."; [ "$QUIET" = "--quiet" ] || pause; return 1; }
  xray_prepare_storage
  xray_fix_service_access
  systemctl enable xray >/dev/null 2>&1 || true

  # Do not repeatedly reinstall the core when a JSON configuration is wrong.
  # A valid existing configuration is restarted; otherwise option 2/create-user
  # will regenerate and validate the configuration without another download.
  if [ -f "$XRAY_CONFIG" ]; then
    if xray_test_file "$XRAY_CONFIG"; then
      xray_restart_safe || return 1
    else
      echo "Xray core installed, but the existing config needs regeneration."
      [ -n "${XRAY_TEST_ERROR:-}" ] && printf '%s\n' "$XRAY_TEST_ERROR"
    fi
  fi
  echo "Xray installed: $(xray_version_text)"
  [ "$QUIET" = "--quiet" ] || pause
}

xray_seed_uuid(){
  local H
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
    return
  fi
  if [ -r /proc/sys/kernel/random/uuid ]; then
    tr -d '\n' </proc/sys/kernel/random/uuid
    echo
    return
  fi
  H="$(openssl rand -hex 16 2>/dev/null || date +%s%N | sha256sum | awk '{print substr($1,1,32)}')"
  printf '%s-%s-%s-%s-%s\n' "${H:0:8}" "${H:8:4}" "${H:12:4}" "${H:16:4}" "${H:20:12}"
}

write_xray_ws_config(){
  local FILE="$1" MODE="${2:-stats}" VLESS_SEED VMESS_SEED TROJAN_SEED VLESS_PATH VMESS_PATH TROJAN_PATH
  VLESS_SEED="$(xray_seed_uuid)"
  VMESS_SEED="$(xray_seed_uuid)"
  TROJAN_SEED="$(openssl rand -hex 24)"
  VLESS_PATH="$(xray_saved_path vless-ws)"
  VMESS_PATH="$(xray_saved_path vmess-ws)"
  TROJAN_PATH="$(xray_saved_path trojan-ws)"
  if [ "$MODE" = "stats" ]; then
    cat >"$FILE" <<EOF
{
  "log": {"loglevel": "warning"},
  "stats": {},
  "api": {"tag": "api", "listen": "127.0.0.1:10090", "services": ["StatsService"]},
  "policy": {
    "levels": {"0": {"statsUserUplink": true, "statsUserDownlink": true}},
    "system": {"statsInboundUplink": true, "statsInboundDownlink": true, "statsOutboundUplink": true, "statsOutboundDownlink": true}
  },
  "inbounds": [
    {
      "tag": "vless-ws",
      "listen": "127.0.0.1",
      "port": 10000,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$VLESS_SEED", "email": "_sultan_placeholder_vless", "level": 0}], "decryption": "none"},
      "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "$VLESS_PATH"}}
    },
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$VMESS_SEED", "email": "_sultan_placeholder_vmess", "level": 0}]},
      "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "$VMESS_PATH"}}
    },
    {
      "tag": "trojan-ws",
      "listen": "127.0.0.1",
      "port": 10086,
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$TROJAN_SEED", "email": "_sultan_placeholder_trojan", "level": 0}]},
      "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "$TROJAN_PATH"}}
    }
  ],
  "outbounds": [{"tag": "direct", "protocol": "direct", "settings": {}}]
}
EOF
  else
    cat >"$FILE" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "tag": "vless-ws",
      "listen": "127.0.0.1",
      "port": 10000,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$VLESS_SEED", "email": "_sultan_placeholder_vless", "level": 0}], "decryption": "none"},
      "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "$VLESS_PATH"}}
    },
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$VMESS_SEED", "email": "_sultan_placeholder_vmess", "level": 0}]},
      "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "$VMESS_PATH"}}
    },
    {
      "tag": "trojan-ws",
      "listen": "127.0.0.1",
      "port": 10086,
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$TROJAN_SEED", "email": "_sultan_placeholder_trojan", "level": 0}]},
      "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "$TROJAN_PATH"}}
    }
  ],
  "outbounds": [{"tag": "direct", "protocol": "direct", "settings": {}}]
}
EOF
  fi
}

xray_sync_users_from_db(){
  local DBF U VALUE P NET DOMAIN PATHX_DB EXP QUOTA LOGIN CREATED REST TAG FILTER
  command -v jq >/dev/null 2>&1 || return 1
  [ -f "$XRAY_CONFIG" ] || return 1

  for TAG in vless-ws vmess-ws trojan-ws; do
    DBF="$XDB/$TAG.db"
    [ -f "$DBF" ] || continue
    while IFS='|' read -r U VALUE P NET DOMAIN PATHX_DB EXP QUOTA LOGIN CREATED REST; do
      [ -n "$U" ] || continue
      [ -n "$VALUE" ] || continue
      case "$TAG" in
        trojan-ws)
          FILTER='
            (.inbounds[]|select(.tag==$tag)|.settings.clients) |=
            ((. // []) | if any(.[]?; .email==$email or .password==$value) then . else . + [{"password":$value,"email":$email,"level":0}] end)
          '
          ;;
        vmess-ws)
          FILTER='
            (.inbounds[]|select(.tag==$tag)|.settings.clients) |=
            ((. // []) | if any(.[]?; .email==$email or .id==$value) then . else . + [{"id":$value,"email":$email,"level":0}] end)
          '
          ;;
        vless-ws)
          FILTER='
            (.inbounds[]|select(.tag==$tag)|.settings.clients) |=
            ((. // []) | if any(.[]?; .email==$email or .id==$value) then . else . + [{"id":$value,"email":$email,"level":0}] end)
          '
          ;;
      esac
      xray_jq_update "$FILTER" --arg value "$VALUE" --arg email "$U" --arg tag "$TAG" || return 1
    done < "$DBF"
  done
}

create_xray_config(){
  local QUIET="${1:-}" TMP_CFG STATS_ENABLED=1 BIN STATS_ERROR=""
  [ "$QUIET" = "--quiet" ] || refresh_screen
  xray_prepare_storage
  BIN="$(xray_binary 2>/dev/null || true)"
  if [ -z "$BIN" ]; then
    echo "Xray core is missing. Installing the latest official core..."
    install_xray --quiet || return 1
    BIN="$(xray_binary 2>/dev/null || true)"
    [ -n "$BIN" ] || { echo "Xray binary is still missing."; return 1; }
  fi

  TMP_CFG="$(mktemp --suffix=.json "/usr/local/etc/xray/.config.XXXXXX")" || { echo "Cannot create temp config."; return 1; }
  write_xray_ws_config "$TMP_CFG" stats
  chmod 600 "$TMP_CFG"

  if ! xray_test_file "$TMP_CFG"; then
    STATS_ERROR="${XRAY_TEST_ERROR:-}"
    write_xray_ws_config "$TMP_CFG" basic
    chmod 600 "$TMP_CFG"
    STATS_ENABLED=0
  fi

  if ! xray_test_file "$TMP_CFG"; then
    echo "Xray rejected the generated WebSocket configuration."
    echo "Detected core: $(xray_version_text)"
    [ -n "$STATS_ERROR" ] && { echo "Stats configuration error:"; printf '%s\n' "$STATS_ERROR"; }
    [ -n "${XRAY_TEST_ERROR:-}" ] && { echo "Basic configuration error:"; printf '%s\n' "$XRAY_TEST_ERROR"; }
    rm -f "$TMP_CFG"
    [ "$QUIET" = "--quiet" ] || pause
    return 1
  fi

  [ -f "$XRAY_CONFIG" ] && cp -a "$XRAY_CONFIG" "$XRAY_CONFIG.sultan.bak.$(date +%Y%m%d%H%M%S)"
  mv -f "$TMP_CFG" "$XRAY_CONFIG"
  chown root:root "$XRAY_CONFIG"
  chmod 600 "$XRAY_CONFIG"
  xray_fix_service_access
  if ! xray_sync_users_from_db; then
    echo "Failed to synchronize saved Xray users."
    [ "$QUIET" = "--quiet" ] || pause
    return 1
  fi
  xray_restart_safe || { [ "$QUIET" = "--quiet" ] || pause; return 1; }
  echo "Xray WebSocket config created and verified."
  [ "$STATS_ENABLED" = "0" ] && echo "Stats API was skipped; VLESS/VMess/Trojan WebSocket remains enabled."
  [ "$QUIET" = "--quiet" ] || pause
}

ensure_xray_config(){
  local BIN
  command -v jq >/dev/null 2>&1 || { echo "jq is missing. Run server install first."; return 1; }
  BIN="$(xray_binary 2>/dev/null || true)"
  if [ -z "$BIN" ]; then
    install_xray --quiet || return 1
  fi
  if [ ! -f "$XRAY_CONFIG" ] || ! jq -e '.inbounds and .outbounds' "$XRAY_CONFIG" >/dev/null 2>&1; then
    create_xray_config --quiet || return 1
  elif ! jq -e '
    ([.inbounds[]? | select(.tag=="vless-ws" or .tag=="vmess-ws" or .tag=="trojan-ws")] | length) == 3 and
    all(.inbounds[]? | select(.tag=="vless-ws" or .tag=="vmess-ws" or .tag=="trojan-ws");
      ((.settings.clients | type) == "array") and
      ((.settings.clients | length) > 0) and
      ((.settings | has("users")) | not) and
      (.streamSettings.network == "ws") and
      ((.streamSettings | has("method")) | not) and
      ((.streamSettings.wsSettings.path // "") | startswith("/"))
    )
  ' "$XRAY_CONFIG" >/dev/null 2>&1; then
    echo "Migrating the old Xray WebSocket schema without reinstalling the core."
    create_xray_config --quiet || return 1
  elif ! xray_test_file "$XRAY_CONFIG"; then
    echo "Existing Xray config is incompatible; rebuilding it without reinstalling the core."
    [ -n "${XRAY_TEST_ERROR:-}" ] && printf '%s\n' "$XRAY_TEST_ERROR"
    create_xray_config --quiet || return 1
  fi
  xray_test_file "$XRAY_CONFIG"
}

create_xray_user(){
  local PROTO="$1" TAG="$2" DEFAULT_PATH="$3" DBF VALUE DOMAIN FILTER BACKUP LOCKF DAYS GB MAXLOGIN EXP QUOTA_TEXT LOGIN_TEXT LINK WS_CODE
  local CURRENT_PATH INPUT_PATH PATHX CONFIRM CLIENT_ADDR CLIENT_HOST CLIENT_SNI ALLOW_INSECURE AI_ANSWER
  ensure_xray_config || { echo "Xray config is not ready."; pause; return; }

  DBF="$XDB/$TAG.db"
  mkdir -p "$XDB"
  touch "$DBF"
  chmod 600 "$DBF" 2>/dev/null || true

  CURRENT_PATH="$(xray_current_path "$TAG" "$DEFAULT_PATH")"

  refresh_screen
  echo "==================================="
  echo "        CREATE ${PROTO^^} WS USER"
  echo "==================================="
  show_xray_users_table "$DBF" "${PROTO^^}" 2>/dev/null || true
  echo ""
  printf "%-20s : %s\n" "Current WS Path" "$CURRENT_PATH"
  read -p "WebSocket Path [Enter = keep, example: vless or /vpn/vless]: " INPUT_PATH
  [ -n "$INPUT_PATH" ] && PATHX="$INPUT_PATH" || PATHX="$CURRENT_PATH"

  PATHX="$(normalize_ws_path "$PATHX")" || {
    echo "Invalid path."
    echo "Allowed examples: /vless-ws, vless, /vless, /vpn/vless, /abc-123_test"
    echo "Do not use spaces, Arabic letters, or query symbols."
    pause
    return
  }

  if [ "$PATHX" != "$CURRENT_PATH" ]; then
    if [ -s "$DBF" ]; then
      echo ""
      echo "This protocol uses one shared WebSocket path."
      echo "Changing it updates the links of all existing ${PROTO^^} users."
      read -p "Type YES to continue: " CONFIRM
      [ "$CONFIRM" = "YES" ] || { echo "Cancelled."; pause; return; }
    fi
    xray_set_protocol_path "$TAG" "$PATHX" "$DBF" || { pause; return; }
  else
    # Rebuild the reverse proxy from the live Xray path. This repairs old
    # installations where Nginx still points at a stale hard-coded path.
    refresh_proxy_config_from_current || { echo "Proxy path synchronization failed."; pause; return; }
  fi

  read -p "Username: " USER
  read -p "Days (0 = Unlimited): " DAYS
  read -p "GB Limit (0 = Unlimited): " GB
  read -p "Users/Login Limit (0 = Unlimited): " MAXLOGIN
  validate_xray_username "$USER" || { echo "Invalid Xray username."; pause; return; }
  [[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "Invalid days value."; pause; return; }
  [[ "$GB" =~ ^[0-9]+$ ]] || { echo "Invalid GB value."; pause; return; }
  [[ "$MAXLOGIN" =~ ^[0-9]+$ ]] || { echo "Invalid users value."; pause; return; }
  DAYS=$((10#$DAYS))
  GB=$((10#$GB))
  MAXLOGIN=$((10#$MAXLOGIN))
  [ "$DAYS" -le 36500 ] || { echo "Invalid days value."; pause; return; }
  [ "$GB" -le 1000000 ] || { echo "Invalid GB value."; pause; return; }
  [ "$MAXLOGIN" -le 1000 ] || { echo "Invalid users value."; pause; return; }

  DOMAIN="$(get_domain)"
  [ "$DOMAIN" != "Not Set" ] && validate_domain "$DOMAIN" || { echo "Set a valid domain first."; pause; return; }

  echo ""
  echo "Client TLS/WS link options:"
  read -p "Connection Address/Server [Enter = $DOMAIN]: " CLIENT_ADDR
  [ -n "$CLIENT_ADDR" ] || CLIENT_ADDR="$DOMAIN"
  validate_link_address "$CLIENT_ADDR" || { echo "Invalid Address/Server. Use a domain or IPv4."; pause; return; }
  read -p "Custom Host/SNI [Enter = $DOMAIN]: " CLIENT_HOST
  [ -n "$CLIENT_HOST" ] || CLIENT_HOST="$DOMAIN"
  validate_domain "$CLIENT_HOST" || { echo "Invalid Host/SNI domain."; pause; return; }
  read -p "Custom SNI [Enter = $CLIENT_HOST]: " CLIENT_SNI
  [ -n "$CLIENT_SNI" ] || CLIENT_SNI="$CLIENT_HOST"
  validate_domain "$CLIENT_SNI" || { echo "Invalid SNI domain."; pause; return; }
  read -p "Allow Insecure? [y/N]: " AI_ANSWER
  case "$AI_ANSWER" in
    y|Y|yes|YES|1|true|TRUE|on|ON) ALLOW_INSECURE=1 ;;
    *) ALLOW_INSECURE=0 ;;
  esac

  grep -q "^${USER}|" "$DBF" 2>/dev/null && { echo "User already exists"; pause; return; }
  jq -e --arg tag "$TAG" 'any(.inbounds[]?; .tag==$tag)' "$XRAY_CONFIG" >/dev/null ||
    { echo "Inbound tag missing: $TAG"; pause; return; }

  if [ "$DAYS" = "0" ]; then
    EXP="0"
  else
    EXP="$(date -d "+$DAYS days" +%Y-%m-%d)"
  fi
  [ "$GB" = "0" ] && QUOTA_TEXT="0" || QUOTA_TEXT="${GB}GB"
  [ "$MAXLOGIN" = "0" ] && LOGIN_TEXT="0" || LOGIN_TEXT="$MAXLOGIN"

  if [ "$PROTO" = "trojan" ]; then
    VALUE="$(openssl rand -hex 16)"
    FILTER='(.inbounds[]|select(.tag==$tag)|.settings.clients)+=[{"password":$value,"email":$email,"level":0}]'
  else
    VALUE="$(xray_seed_uuid)"
    FILTER='(.inbounds[]|select(.tag==$tag)|.settings.clients)+=[{"id":$value,"email":$email,"level":0}]'
  fi

  BACKUP="$(mktemp --suffix=.json "/usr/local/etc/xray/.rollback.XXXXXX")" || { echo "Rollback temp failed."; pause; return; }
  cp -a "$XRAY_CONFIG" "$BACKUP"

  xray_jq_update "$FILTER" --arg value "$VALUE" --arg email "$USER" --arg tag "$TAG" || {
    rm -f "$BACKUP"
    echo "Failed to update or validate Xray config."
    pause
    return
  }

  if ! xray_restart_safe; then
    cp -a "$BACKUP" "$XRAY_CONFIG"
    xray_restart_safe >/dev/null 2>&1 || true
    rm -f "$BACKUP"
    echo "Xray restart failed; config was rolled back."
    pause
    return
  fi

  if ! refresh_proxy_config_from_current; then
    cp -a "$BACKUP" "$XRAY_CONFIG"
    xray_restart_safe >/dev/null 2>&1 || true
    refresh_proxy_config_from_current >/dev/null 2>&1 || true
    rm -f "$BACKUP"
    echo "Proxy reload failed; Xray user was rolled back."
    pause
    return
  fi

  # Verify the public WebSocket route, but do not roll back the user only
  # because curl did not receive 101. Some Xray/WebSocket builds answer the
  # raw curl handshake differently while real clients still work.
  #
  # The authoritative checks here are:
  # 1) Xray JSON test inside xray_jq_update
  # 2) xray service restart
  # 3) Nginx/HAProxy config test inside refresh_proxy_config_from_current
  if [ "$PROTO" = "vless" ]; then
    WS_CODE="$(websocket_status_code "$DOMAIN" "$PATHX")"
    if [ "$WS_CODE" != "101" ]; then
      echo "Warning: WebSocket probe returned HTTP ${WS_CODE:-000}; keeping the user because Xray config is valid."
      echo "Run Full WebSocket Test from the menu if the client still cannot connect."
    fi
  fi

  LOCKF="$XDB/$TAG.lock"
  if ! (
    flock -x 7
    printf '%s|%s|%s|ws|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$USER" "$VALUE" "$PROTO" "$DOMAIN" "$PATHX" "$EXP" "$QUOTA_TEXT" "$LOGIN_TEXT" "$(date +%s)" "$CLIENT_HOST" "$CLIENT_SNI" "$ALLOW_INSECURE" "$CLIENT_ADDR" >> "$DBF"
    chmod 600 "$DBF" 2>/dev/null || true
  ) 7>"$LOCKF"; then
    cp -a "$BACKUP" "$XRAY_CONFIG"
    xray_restart_safe >/dev/null 2>&1 || true
    rm -f "$BACKUP"
    echo "User database update failed; Xray change was rolled back."
    pause
    return
  fi

  rm -f "$BACKUP"
  LINK="$(xray_link "$PROTO" "$USER" "$VALUE" "$CLIENT_ADDR" "$PATHX" "$CLIENT_HOST" "$CLIENT_SNI" "$ALLOW_INSECURE")"

  refresh_screen
  echo "==================================="
  echo "        ${PROTO^^} WS USER CREATED"
  echo "==================================="
  box "Username" "$USER"
  box "ID/Password" "$VALUE"
  box "Expire" "$EXP"
  box "Quota" "$QUOTA_TEXT"
  box "Users Limit" "$LOGIN_TEXT"
  box "Address" "$CLIENT_ADDR"
  [ "$CLIENT_ADDR" != "$DOMAIN" ] && box "Origin Domain" "$DOMAIN"
  box "Port" "443"
  box "Host" "$CLIENT_HOST"
  box "SNI" "$CLIENT_SNI"
  box "Allow Insecure" "$ALLOW_INSECURE"
  box "Path" "$PATHX"
  [ "$PROTO" = "vless" ] && box "Xray Config" "VERIFIED"
  echo "-----------------------------------"
  echo "Ready Link:"
  echo "$LINK"
  echo "-----------------------------------"
  pause
}

delete_xray_user(){
  local PROTO="$1" TAG="$2" FIELD="$3" DBF VALUE FILTER TMP BACKUP LOCKF
  refresh_screen
  DBF="$XDB/$TAG.db"
  select_xray_user "$DBF" "${PROTO^^}" || { pause; return; }
  VALUE="$(awk -F'|' -v u="$USER" '$1==u{print $2;exit}' "$DBF" 2>/dev/null)"

  [ -n "$VALUE" ] || { echo "User not found"; pause; return; }

  if [ "$FIELD" = "password" ]; then
    FILTER='(.inbounds[]|select(.tag==$tag)|.settings.clients)|=map(select(.password!=$value))'
  else
    FILTER='(.inbounds[]|select(.tag==$tag)|.settings.clients)|=map(select(.id!=$value))'
  fi

  BACKUP="$(mktemp "/usr/local/etc/xray/.rollback.XXXXXX")" || { echo "Rollback temp failed."; pause; return; }
  cp -a "$XRAY_CONFIG" "$BACKUP"
  xray_jq_update "$FILTER" --arg value "$VALUE" --arg tag "$TAG" ||
    { rm -f "$BACKUP"; echo "Failed to update or validate Xray config."; pause; return; }
  if ! xray_restart_safe; then
    cp -a "$BACKUP" "$XRAY_CONFIG"
    xray_restart_safe >/dev/null 2>&1 || true
    rm -f "$BACKUP"
    echo "Xray restart failed; config was rolled back."
    pause
    return
  fi
  rm -f "$BACKUP"
  LOCKF="$XDB/$TAG.lock"
  (
    flock -x 7
    TMP="$(mktemp "$XDB/.${TAG}.XXXXXX")" || exit 1
    awk -F'|' -v u="$USER" '$1!=u' "$DBF" > "$TMP" || { rm -f "$TMP"; exit 1; }
    chmod 600 "$TMP"
    mv -f "$TMP" "$DBF"
  ) 7>"$LOCKF" || { echo "Xray user DB update failed."; pause; return; }
  if [ -f /etc/nginx/conf.d/sultan-ready.conf ]; then
    nginx_haproxy_restart_safe || { echo "Proxy reload failed."; pause; return; }
  fi
  echo "Deleted: $USER"
  pause
}

show_xray_user_statistics(){
  local PROTO="$1" TAG="$2" DBF="$XDB/$TAG.db" LINE U VALUE NET DOMAIN PATHX EXP QUOTA LOGIN CREATED CLIENT_HOST CLIENT_SNI ALLOW_INSECURE CLIENT_ADDR USED LIMIT REMAIN LINK LEFT_TEXT
  refresh_screen
  select_xray_user "$DBF" "${PROTO^^}" || { pause; return; }
  LINE="$(awk -F'|' -v u="$USER" '$1==u{print;exit}' "$DBF" 2>/dev/null)"
  [ -n "$LINE" ] || { echo "User not found."; pause; return; }
  IFS='|' read -r U VALUE PROTO NET DOMAIN PATHX EXP QUOTA LOGIN CREATED CLIENT_HOST CLIENT_SNI ALLOW_INSECURE CLIENT_ADDR REST <<< "$LINE"
  [ -n "$EXP" ] || EXP="0"
  [ -n "$QUOTA" ] || QUOTA="Unlimited"
  [ -n "$LOGIN" ] || LOGIN="Unlimited"
  validate_domain "$CLIENT_HOST" || CLIENT_HOST="$DOMAIN"
  validate_domain "$CLIENT_SNI" || CLIENT_SNI="$CLIENT_HOST"
  case "$ALLOW_INSECURE" in 1|y|Y|yes|YES|true|TRUE|on|ON) ALLOW_INSECURE=1 ;; *) ALLOW_INSECURE=0 ;; esac
  validate_link_address "$CLIENT_ADDR" || CLIENT_ADDR="$DOMAIN"
  USED="$(xray_user_used_bytes "$U")"
  LIMIT="$(quota_bytes_from_text "$QUOTA")"
  if [ "$LIMIT" -eq 0 ]; then
    REMAIN="Unlimited"
  elif [ "$USED" -ge "$LIMIT" ]; then
    REMAIN="0 B"
  else
    REMAIN="$(human_bytes $((LIMIT-USED)))"
  fi
  LEFT_TEXT="$(remaining_exact "$EXP")"
  LINK="$(xray_link "$PROTO" "$U" "$VALUE" "$CLIENT_ADDR" "$PATHX" "$CLIENT_HOST" "$CLIENT_SNI" "$ALLOW_INSECURE")"

  refresh_screen
  echo "========================================"
  echo "        ${PROTO^^} WS STATISTICS"
  echo "========================================"
  printf "%-16s : %s\n" "Username" "$U"
  printf "%-16s : %s\n" "Protocol" "${PROTO^^} WebSocket TLS"
  printf "%-16s : %s\n" "Used Traffic" "$(human_bytes "$USED")"
  printf "%-16s : %s\n" "Traffic Limit" "$QUOTA"
  printf "%-16s : %s\n" "Traffic Left" "$REMAIN"
  echo "----------------------------------------"
  printf "%-16s : %s\n" "Users Limit" "$LOGIN"
  printf "%-16s : %s\n" "Expire Date" "$EXP"
  printf "%-16s : %s\n" "Time Left" "$LEFT_TEXT"
  printf "%-16s : %s\n" "Address" "$CLIENT_ADDR"
  [ "$CLIENT_ADDR" != "$DOMAIN" ] && printf "%-16s : %s\n" "Origin Domain" "$DOMAIN"
  printf "%-16s : %s\n" "Host" "$CLIENT_HOST"
  printf "%-16s : %s\n" "SNI" "$CLIENT_SNI"
  printf "%-16s : %s\n" "Allow Insecure" "$ALLOW_INSECURE"
  printf "%-16s : %s\n" "Path" "$PATHX"
  echo "----------------------------------------"
  echo "Ready Link:"
  echo "$LINK"
  echo "========================================"
  pause
}

show_xray_traffic_statistics(){
  local PROTO="$1" TAG="$2" DBF="$XDB/$TAG.db"
  local LINE U VALUE NET DOMAIN PATHX EXP QUOTA LOGIN CREATED REST
  local USED LIMIT REMAIN LEFT_TEXT QUOTA_SHOW LOGIN_SHOW EXP_SHOW

  refresh_screen
  select_xray_user "$DBF" "${PROTO^^}" || { pause; return; }
  LINE="$(awk -F'|' -v u="$USER" '$1==u{print;exit}' "$DBF" 2>/dev/null)"
  [ -n "$LINE" ] || { echo "User not found."; pause; return; }
  IFS='|' read -r U VALUE PROTO NET DOMAIN PATHX EXP QUOTA LOGIN CREATED REST <<< "$LINE"

  case "$QUOTA" in
    ""|0|Unlimited|unlimited|UNLIMITED) QUOTA_SHOW="Unlimited" ;;
    *) QUOTA_SHOW="$QUOTA" ;;
  esac
  case "$LOGIN" in
    ""|0|Unlimited|unlimited|UNLIMITED) LOGIN_SHOW="Unlimited" ;;
    *) LOGIN_SHOW="$LOGIN" ;;
  esac
  case "$EXP" in
    ""|0|Unlimited|unlimited|UNLIMITED)
      EXP_SHOW="Unlimited"
      LEFT_TEXT="Unlimited"
      ;;
    *)
      EXP_SHOW="$EXP"
      LEFT_TEXT="$(remaining_exact "$EXP")"
      ;;
  esac

  USED="$(xray_user_used_bytes "$U")"
  LIMIT="$(quota_bytes_from_text "$QUOTA")"
  if [ "$LIMIT" -eq 0 ]; then
    REMAIN="Unlimited"
  elif [ "$USED" -ge "$LIMIT" ]; then
    REMAIN="0 B"
  else
    REMAIN="$(human_bytes $((LIMIT-USED)))"
  fi

  refresh_screen
  echo -e "${ORANGE}========================================${NC}"
  echo -e "${ORANGE}       ${PROTO^^} USER STATISTICS${NC}"
  echo -e "${ORANGE}========================================${NC}"
  printf "%-16s : %s\n" "Username" "$U"
  printf "%-16s : %s\n" "Used Traffic" "$(human_bytes "$USED")"
  printf "%-16s : %s\n" "Traffic Limit" "$QUOTA_SHOW"
  printf "%-16s : %s\n" "Traffic Left" "$REMAIN"
  echo "----------------------------------------"
  printf "%-16s : %s\n" "Users Limit" "$LOGIN_SHOW"
  echo "----------------------------------------"
  printf "%-16s : %s\n" "Expire Date" "$EXP_SHOW"
  printf "%-16s : %s\n" "Time Left" "$LEFT_TEXT"
  echo -e "${ORANGE}========================================${NC}"
  pause
}

change_xray_user_menu(){
  local PROTO="$1" TAG="$2" DBF="$XDB/$TAG.db" ACTION GB MAXLOGIN DAYS EXP QUOTA_TEXT LOGIN_TEXT
  refresh_screen
  select_xray_user "$DBF" "${PROTO^^}" || { pause; return; }
  while true; do
    refresh_screen
    show_xray_users_table "$DBF" "${PROTO^^}"
    echo ""
    echo "(1) Change Traffic Limit"
    echo "(2) Change Users/Login Limit"
    echo "(3) Change Expire"
    echo "(4) Show Statistics + Link"
    echo "(5) Delete User"
    echo "(0) Back"
    read -p "Choose: " ACTION
    case "$ACTION" in
      1)
        read -p "New GB Limit (0 = Unlimited): " GB
        [[ "$GB" =~ ^[0-9]+$ ]] || { echo "Invalid value."; pause; continue; }
        GB=$((10#$GB))
        [ "$GB" = "0" ] && QUOTA_TEXT="0" || QUOTA_TEXT="${GB}GB"
        xray_db_update_field "$DBF" "$USER" 8 "$QUOTA_TEXT" || { echo "Update failed."; pause; continue; }
        echo "Quota changed to $QUOTA_TEXT"; pause
        ;;
      2)
        read -p "New Users/Login Limit (0 = Unlimited): " MAXLOGIN
        [[ "$MAXLOGIN" =~ ^[0-9]+$ ]] || { echo "Invalid value."; pause; continue; }
        MAXLOGIN=$((10#$MAXLOGIN))
        [ "$MAXLOGIN" = "0" ] && LOGIN_TEXT="0" || LOGIN_TEXT="$MAXLOGIN"
        xray_db_update_field "$DBF" "$USER" 9 "$LOGIN_TEXT" || { echo "Update failed."; pause; continue; }
        echo "Users limit changed to $LOGIN_TEXT"; pause
        ;;
      3)
        read -p "Add days (0 = Unlimited): " DAYS
        [[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "Invalid value."; pause; continue; }
        DAYS=$((10#$DAYS))
        [ "$DAYS" = "0" ] && EXP="0" || EXP="$(date -d "+$DAYS days" +%Y-%m-%d)"
        xray_db_update_field "$DBF" "$USER" 7 "$EXP" || { echo "Update failed."; pause; continue; }
        echo "Expire changed to $EXP"; pause
        ;;
      4) show_xray_user_statistics "$PROTO" "$TAG" ;;
      5) delete_xray_user "$PROTO" "$TAG" "$( [ "$PROTO" = "trojan" ] && echo password || echo id )"; return ;;
      0) return ;;
    esac
  done
}

change_xray_path_menu(){
  local PROTO="$1" TAG="$2" DEFAULT_PATH="$3" DBF CURRENT_PATH NEW_PATH CONFIRM
  ensure_xray_config || { echo "Xray config is not ready."; pause; return; }
  DBF="$XDB/$TAG.db"
  touch "$DBF"
  chmod 600 "$DBF" 2>/dev/null || true
  CURRENT_PATH="$(xray_current_path "$TAG" "$DEFAULT_PATH")"

  refresh_screen
  echo "==================================="
  echo "      CHANGE ${PROTO^^} WS PATH"
  echo "==================================="
  printf "%-18s : %s\n" "Current Path" "$CURRENT_PATH"
  echo "Examples: vless | /vless | /vpn/vless | /my-${PROTO}-path"
  echo "==================================="
  read -p "New WebSocket Path (example: vless or /vpn/vless): " NEW_PATH

  NEW_PATH="$(normalize_ws_path "$NEW_PATH")" || {
    echo "Invalid path."
    echo "Allowed examples: /vless-ws, vless, /vless, /vpn/vless, /abc-123_test"
    echo "Do not use spaces, Arabic letters, or query symbols."
    pause
    return
  }
  [ "$NEW_PATH" != "$CURRENT_PATH" ] || { echo "Path is unchanged."; pause; return; }

  if [ -s "$DBF" ]; then
    echo "All existing ${PROTO^^} links will be updated to the new path."
    read -p "Type YES to continue: " CONFIRM
    [ "$CONFIRM" = "YES" ] || { echo "Cancelled."; pause; return; }
  fi

  xray_set_protocol_path "$TAG" "$NEW_PATH" "$DBF" || { pause; return; }
  echo "The new path is active and all saved links were updated."
  pause
}

xray_proto_menu(){
  local PROTO="$1" TAG="$2" PATHX="$3" FIELD="$4"
  mkdir -p "$XDB"
  touch "$XDB/$TAG.db"
  chmod 600 "$XDB/$TAG.db" 2>/dev/null || true
  while true; do
    refresh_screen
    echo "==================================="
    echo "            ${PROTO^^} WS MENU"
    echo "==================================="
    show_xray_users_table "$XDB/$TAG.db" "${PROTO^^}" 2>/dev/null || true
    echo ""
    echo "[1] Create ${PROTO^^} WS User"
    echo "[2] Change User"
    echo "[3] Delete User"
    echo "[4] Show Statistics + Link"
    echo "[5] List Links"
    echo "[6] Change WebSocket Path"
    echo "[7] ${PROTO^^} User Statistics"
    echo "[0] Back"
    read -p "Select: " x
    case "$x" in
      1) create_xray_user "$PROTO" "$TAG" "$PATHX" ;;
      2) change_xray_user_menu "$PROTO" "$TAG" ;;
      3) delete_xray_user "$PROTO" "$TAG" "$FIELD" ;;
      4) show_xray_user_statistics "$PROTO" "$TAG" ;;
      5)
        refresh_screen
        while IFS='|' read -r U VALUE P NET DOMAIN PATHX_DB EXP QUOTA LOGIN CREATED CLIENT_HOST CLIENT_SNI ALLOW_INSECURE CLIENT_ADDR REST; do
          [ -n "$U" ] || continue
          validate_domain "$CLIENT_HOST" || CLIENT_HOST="$DOMAIN"
          validate_domain "$CLIENT_SNI" || CLIENT_SNI="$CLIENT_HOST"
          case "$ALLOW_INSECURE" in 1|y|Y|yes|YES|true|TRUE|on|ON) ALLOW_INSECURE=1 ;; *) ALLOW_INSECURE=0 ;; esac
          validate_link_address "$CLIENT_ADDR" || CLIENT_ADDR="$DOMAIN"
          echo "$U"
          xray_link "$P" "$U" "$VALUE" "$CLIENT_ADDR" "$PATHX_DB" "$CLIENT_HOST" "$CLIENT_SNI" "$ALLOW_INSECURE"
          echo "----------------------------------------"
        done < "$XDB/$TAG.db"
        pause
        ;;
      6) change_xray_path_menu "$PROTO" "$TAG" "$PATHX" ;;
      7) show_xray_traffic_statistics "$PROTO" "$TAG" ;;
      0) return ;;
    esac
  done
}

vmess_menu(){
  xray_proto_menu vmess vmess-ws /vmess-ws id
}
vless_menu(){ xray_proto_menu vless vless-ws /vless-ws id; }
trojan_menu(){ xray_proto_menu trojan trojan-ws /trojan-ws password; }

xray_menu(){
  while true; do
    refresh_screen
    echo "[1] Install/Reinstall Xray"
    echo "[2] Create Base Config"
    echo "[3] Restart Xray"
    echo "[4] Xray Status"
    echo "[5] Full WebSocket Test"
    echo "[0] Back"
    read -p "Select: " x
    case "$x" in
      1) install_xray ;;
      2) create_xray_config ;;
      3) xray_restart_safe; pause ;;
      4) systemctl status xray --no-pager || true; pause ;;
      5) v2ray_ws_verify_or_repair "$(get_domain)"; pause ;;
      0) return ;;
    esac
  done
}

current_session_via_ws(){
  local PEER="${SSH_CONNECTION%% *}"
  case "$PEER" in
    127.0.0.1|::1|localhost) return 0 ;;
    *) return 1 ;;
  esac
}

install_ws(){
  groupadd -r sultan-ws 2>/dev/null || true
  id sultan-ws >/dev/null 2>&1 || useradd -r -g sultan-ws -s /usr/sbin/nologin -d /nonexistent sultan-ws
  ensure_ws_token >/dev/null
  chown root:sultan-ws "$WS_TOKEN_FILE"
  chmod 640 "$WS_TOKEN_FILE"

  cat >/usr/local/bin/sultan-ssh-ws <<'PYWS'
#!/usr/bin/env python3
import asyncio
import base64
import hashlib
import hmac
import os
import struct
import urllib.parse

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
MAX_HEADER = 65536
MAX_FRAME = 1048576
MAX_CONNECTIONS = 128
LISTEN_PORT = int(os.environ.get("SULTAN_WS_LISTEN_PORT", "8080"))
MAP_DIR = "/run/sultan-ws-map"
semaphore = asyncio.Semaphore(MAX_CONNECTIONS)

async def read_http_header(reader):
    return await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=8)

def parse_headers(raw):
    lines = raw.decode("latin1", errors="strict").split("\r\n")
    request = lines[0].split()
    if len(request) != 3 or request[0] != "GET":
        raise ValueError("invalid request")
    headers = {"_path": request[1]}
    for line in lines[1:]:
        if not line:
            continue
        if ":" not in line:
            raise ValueError("invalid header")
        key, value = line.split(":", 1)
        headers[key.strip().lower()] = value.strip()
    return headers

def load_token():
    token_file = os.environ.get("SULTAN_WS_TOKEN_FILE", "/etc/sultan/ws_token")
    try:
        with open(token_file, "r", encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""

def token_allowed(headers):
    # Legacy working login method: old SSH WebSocket clients did not send a
    # custom token. Keep WebSocket authentication exactly like the old scripts:
    # the SSH username/password remains the real authentication layer.
    return True

def client_identity(headers, writer):
    forwarded = headers.get("x-forwarded-for", "").split(",")[0].strip()
    real_ip = headers.get("x-real-ip", "").strip()
    peer = writer.get_extra_info("peername")
    peer_ip = peer[0] if peer else "unknown"
    ip = forwarded or real_ip or peer_ip or "unknown"
    ua = headers.get("user-agent", "")[:300]
    return ip, ua

def write_port_map(port, ip, ua):
    try:
        os.makedirs(MAP_DIR, mode=0o700, exist_ok=True)
        path = os.path.join(MAP_DIR, str(port))
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(f"ip={ip}\n")
            f.write(f"user_agent={ua}\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
        return path
    except OSError:
        return None


async def send_frame(writer, payload, opcode=2):
    length = len(payload)
    first = 0x80 | opcode
    if length < 126:
        header = struct.pack("!BB", first, length)
    elif length <= 65535:
        header = struct.pack("!BBH", first, 126, length)
    else:
        header = struct.pack("!BBQ", first, 127, length)
    writer.write(header + payload)
    await writer.drain()

async def read_frame(reader):
    first, second = await reader.readexactly(2)
    if not first & 0x80:
        raise ValueError("fragmented frame")
    opcode = first & 0x0F
    if not second & 0x80:
        raise ValueError("unmasked frame")
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", await reader.readexactly(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", await reader.readexactly(8))[0]
    if length > MAX_FRAME:
        raise ValueError("frame too large")
    mask = await reader.readexactly(4)
    payload = bytearray(await reader.readexactly(length))
    for index in range(length):
        payload[index] ^= mask[index % 4]
    return opcode, bytes(payload)

async def websocket_to_ssh(client_reader, client_writer, ssh_writer):
    while True:
        opcode, payload = await read_frame(client_reader)
        if opcode in (1, 2):
            ssh_writer.write(payload)
            await ssh_writer.drain()
        elif opcode == 8:
            await send_frame(client_writer, payload[:125], 8)
            return
        elif opcode == 9:
            await send_frame(client_writer, payload[:125], 10)
        elif opcode == 10:
            continue
        else:
            raise ValueError("unsupported opcode")

async def ssh_to_websocket(ssh_reader, client_writer):
    while True:
        data = await ssh_reader.read(16384)
        if not data:
            return
        await send_frame(client_writer, data, 2)

async def handle(client_reader, client_writer):
    ssh_writer = None
    port_map = None
    try:
        async with semaphore:
            raw = await read_http_header(client_reader)
            if len(raw) > MAX_HEADER:
                raise ValueError("header too large")
            headers = parse_headers(raw)
            key = headers.get("sec-websocket-key", "")
            if (
                not key
                or headers.get("upgrade", "").lower() != "websocket"
                or "upgrade" not in headers.get("connection", "").lower()
                or headers.get("sec-websocket-version", "") != "13"
            ):
                client_writer.write(
                    b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
                )
                await client_writer.drain()
                return

            if not token_allowed(headers):
                client_writer.write(
                    b"HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
                )
                await client_writer.drain()
                return

            accept = base64.b64encode(
                hashlib.sha1((key + GUID).encode("ascii")).digest()
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

            ssh_reader, ssh_writer = await asyncio.wait_for(asyncio.open_connection("127.0.0.1", 22), timeout=8)
            sock = ssh_writer.get_extra_info("socket")
            if sock is not None:
                local_port = sock.getsockname()[1]
                ip, ua = client_identity(headers, client_writer)
                port_map = write_port_map(local_port, ip, ua)
            tasks = [
                asyncio.create_task(websocket_to_ssh(client_reader, client_writer, ssh_writer)),
                asyncio.create_task(ssh_to_websocket(ssh_reader, client_writer)),
            ]
            done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in pending:
                task.cancel()
            await asyncio.gather(*pending, return_exceptions=True)
            for task in done:
                task.result()
    except (asyncio.IncompleteReadError, asyncio.TimeoutError, ConnectionError, ValueError):
        pass
    except Exception:
        pass
    finally:
        if port_map:
            try:
                os.unlink(port_map)
            except OSError:
                pass
        if ssh_writer is not None:
            ssh_writer.close()
            try:
                await ssh_writer.wait_closed()
            except Exception:
                pass
        client_writer.close()
        try:
            await client_writer.wait_closed()
        except Exception:
            pass

async def main():
    server = await asyncio.start_server(
        handle,
        "127.0.0.1",
        LISTEN_PORT,
        limit=MAX_HEADER,
        reuse_address=True,
    )
    async with server:
        await server.serve_forever()

asyncio.run(main())
PYWS

  chown root:sultan-ws /usr/local/bin/sultan-ssh-ws
  chmod 750 /usr/local/bin/sultan-ssh-ws

  cat >/etc/systemd/system/sultan-ws.service <<'EOF'
[Unit]
Description=SULTAN SSH WebSocket
After=network.target ssh.service
Wants=ssh.service

[Service]
Environment=SULTAN_WS_TOKEN_FILE=/etc/sultan/ws_token
Environment=SULTAN_WS_LISTEN_PORT=8080
ExecStart=/usr/local/bin/sultan-ssh-ws
Restart=always
RestartSec=2
User=sultan-ws
Group=sultan-ws
RuntimeDirectory=sultan-ws-map
RuntimeDirectoryMode=0700
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  runuser -u sultan-ws -- test -r /usr/local/bin/sultan-ssh-ws || {
    echo "WebSocket service user cannot read its executable."
    return 1
  }
  runuser -u sultan-ws -- test -x /usr/local/bin/sultan-ssh-ws || {
    echo "WebSocket service user cannot execute its program."
    return 1
  }
  systemctl reset-failed sultan-ws >/dev/null 2>&1 || true
  systemctl enable sultan-ws >/dev/null 2>&1 || true
  if current_session_via_ws; then
    # Keep the process that carries the current SSH session alive.
    # The updated legacy unit will start on next reboot or after logout.
    defer_ws_restart_until_logout || true
    echo "WebSocket service files saved; restart skipped now to protect this SSH session."
  else
    checked_restart sultan-ws || return 1
  fi
}

install_udp(){
  groupadd -r sultan-udp 2>/dev/null || true
  id sultan-udp >/dev/null 2>&1 || useradd -r -g sultan-udp -s /usr/sbin/nologin -d /nonexistent sultan-udp
  cat >/usr/local/bin/sultan-udp-relay <<'PYUDP'
#!/usr/bin/env python3
import asyncio
import os

LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 7300
UPSTREAM_HOST = os.environ.get("SULTAN_UDP_UPSTREAM_HOST", "1.1.1.1")
UPSTREAM_PORT = int(os.environ.get("SULTAN_UDP_UPSTREAM_PORT", "53"))
TIMEOUT = 15

class Relay(asyncio.DatagramProtocol):
    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, client):
        asyncio.create_task(self.forward(data, client))

    async def forward(self, data, client):
        loop = asyncio.get_running_loop()
        future = loop.create_future()

        class Upstream(asyncio.DatagramProtocol):
            def connection_made(self, transport):
                self.transport = transport
                transport.sendto(data)

            def datagram_received(self, response, address):
                if not future.done():
                    future.set_result(response)
                self.transport.close()

            def error_received(self, error):
                if not future.done():
                    future.set_exception(error)

        transport = None
        try:
            transport, _ = await loop.create_datagram_endpoint(
                Upstream,
                remote_addr=(UPSTREAM_HOST, UPSTREAM_PORT),
            )
            response = await asyncio.wait_for(future, TIMEOUT)
            self.transport.sendto(response, client)
        except Exception:
            pass
        finally:
            if transport is not None:
                transport.close()

async def main():
    loop = asyncio.get_running_loop()
    transport, _ = await loop.create_datagram_endpoint(
        Relay,
        local_addr=(LISTEN_HOST, LISTEN_PORT),
    )
    try:
        await asyncio.Future()
    finally:
        transport.close()

asyncio.run(main())
PYUDP

  chown root:sultan-udp /usr/local/bin/sultan-udp-relay
  chmod 750 /usr/local/bin/sultan-udp-relay

  cat >/etc/systemd/system/udp-custom.service <<'EOF'
[Unit]
Description=UDP Custom 7300
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/sultan-udp-relay
Restart=always
RestartSec=2
User=sultan-udp
Group=sultan-udp
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  runuser -u sultan-udp -- test -r /usr/local/bin/sultan-udp-relay || {
    echo "UDP service user cannot read its executable."
    return 1
  }
  runuser -u sultan-udp -- test -x /usr/local/bin/sultan-udp-relay || {
    echo "UDP service user cannot execute its program."
    return 1
  }
  systemctl reset-failed udp-custom >/dev/null 2>&1 || true
  systemctl enable udp-custom >/dev/null 2>&1 || true
  checked_restart udp-custom || return 1
  ufw allow 7300/udp 2>/dev/null || true
}

create_self_signed_cert(){
  local D="$1"
  mkdir -p "/etc/sultan/selfsigned/$D"
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout "/etc/sultan/selfsigned/$D/privkey.pem" \
    -out "/etc/sultan/selfsigned/$D/fullchain.pem" \
    -subj "/CN=$D" >/dev/null 2>&1
  chmod 600 "/etc/sultan/selfsigned/$D/privkey.pem" "/etc/sultan/selfsigned/$D/fullchain.pem"
}

ssh_ports(){
  sshd -T 2>/dev/null | awk '$1=="port"{print $2}' | sort -n -u
}

open_main_ports(){
  local P PORTS CURRENT_PORT ALL_PORTS
  PORTS="$(ssh_ports)"
  CURRENT_PORT="$(printf '%s\n' "${SSH_CONNECTION:-}" | awk '{print $4}')"
  ALL_PORTS="$PORTS"
  [[ "$CURRENT_PORT" =~ ^[0-9]+$ ]] && ALL_PORTS="$ALL_PORTS $CURRENT_PORT"
  [ -n "$ALL_PORTS" ] || ALL_PORTS="22"

  for P in $(printf '%s\n' $ALL_PORTS | awk '/^[0-9]+$/' | sort -n -u); do
    ufw allow "$P/tcp" >/dev/null || return 1
  done
  ufw allow 80/tcp >/dev/null || return 1
  ufw allow 443/tcp >/dev/null || return 1
  ufw allow 7300/udp >/dev/null || return 1

  # Do not enable a previously inactive firewall in the middle of a remote
  # installation. Enabling it can terminate a management connection that is
  # using a proxy or a port not visible in sshd -T. Existing active UFW setups
  # are reloaded after the current SSH port has been explicitly allowed.
  if ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw reload >/dev/null || return 1
  else
    echo "UFW rules were prepared. UFW was left inactive to protect this SSH session."
  fi
}

write_nginx_config(){
  local D="$1" CERT="$2" KEY="$3" WS_TOKEN="$4" VLESS_PATH VMESS_PATH TROJAN_PATH
  VLESS_PATH="$(xray_current_path vless-ws /vless-ws)"
  VMESS_PATH="$(xray_current_path vmess-ws /vmess-ws)"
  TROJAN_PATH="$(xray_current_path trojan-ws /trojan-ws)"
  mkdir -p /var/www/sultan-acme /etc/nginx/conf.d
  chmod 755 /var/www/sultan-acme
  cat >/etc/nginx/conf.d/sultan-ready.conf <<EOF
upstream sultan_ssh_ws_backend {
    server 127.0.0.1:8080 max_fails=1 fail_timeout=1s;
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name $D;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/sultan-acme;
        default_type text/plain;
    }

    location / {
        return 200 "SULTAN 200 OK";
        add_header Content-Type text/plain;
    }
}

server {
    listen 127.0.0.1:8443 ssl http2;
    server_name $D;
    ssl_certificate $CERT;
    ssl_certificate_key $KEY;

    location = $VLESS_PATH {
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    location = $VMESS_PATH {
        proxy_pass http://127.0.0.1:10085;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    location = $TROJAN_PATH {
        proxy_pass http://127.0.0.1:10086;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    # New secure path remains available for existing v14 clients.
    location = /sshws-$WS_TOKEN {
        proxy_pass http://sultan_ssh_ws_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    # Legacy working login method: any WebSocket Upgrade request on / (or an
    # arbitrary old path) is forwarded to SSH. The token is injected internally,
    # so old clients do not need to know it.
    location / {
        if (\$http_upgrade = "") { return 200 "SULTAN 200 OK"; }
        proxy_pass http://sultan_ssh_ws_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF
}

write_haproxy_config(){
  if [ -f /etc/haproxy/haproxy.cfg ] && ! grep -q "SULTAN MANAGED" /etc/haproxy/haproxy.cfg; then
    cp -a /etc/haproxy/haproxy.cfg "/etc/haproxy/haproxy.cfg.sultan.bak.$(date +%Y%m%d%H%M%S)"
  fi
  cat >/etc/haproxy/haproxy.cfg <<'EOF'
# SULTAN MANAGED
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
}


wait_service_active(){
  local SERVICE="$1" TRY
  for TRY in {1..20}; do
    systemctl is-active --quiet "$SERVICE" 2>/dev/null && return 0
    sleep 1
  done
  echo "Service did not become active: $SERVICE"
  systemctl status "$SERVICE" --no-pager 2>/dev/null || true
  return 1
}

wait_tcp_listener(){
  local PORT="$1" TRY
  for TRY in {1..20}; do
    if ss -H -ltn "sport = :$PORT" 2>/dev/null | grep -q .; then
      return 0
    fi
    sleep 1
  done
  echo "TCP listener is missing on port: $PORT"
  return 1
}

websocket_status_code(){
  local D="$1" PATHX="$2"
  curl -sk --http1.1 --max-time 4 --connect-timeout 3 \
    --resolve "$D:443:127.0.0.1" \
    -H 'Connection: Upgrade' \
    -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: c3VsdGFuLXZpcC10ZXN0LQ==' \
    -o /dev/null -w '%{http_code}' "https://$D$PATHX" 2>/dev/null || true
}

direct_websocket_status_code(){
  local PORT="$1" PATHX="$2" D="$3"
  curl -s --http1.1 --max-time 4 --connect-timeout 3 \
    -H "Host: $D" \
    -H 'Connection: Upgrade' \
    -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: c3VsdGFuLXZpcC10ZXN0LQ==' \
    -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT$PATHX" 2>/dev/null || true
}

xray_force_ws_compat(){
  local TMP BACKUP
  [ -f "$XRAY_CONFIG" ] || {
    echo "Xray configuration is missing."
    return 1
  }

  TMP="$(mktemp --suffix=.json "/usr/local/etc/xray/.ws-compat.XXXXXX")" || return 1
  BACKUP="${XRAY_CONFIG}.pre-502-fix.$(date +%Y%m%d%H%M%S)"
  cp -a "$XRAY_CONFIG" "$BACKUP" || {
    rm -f "$TMP"
    return 1
  }

  if ! jq '
    # Xray 26.3.27 silently ignores inbound settings.users. Migrate every
    # existing account into settings.clients before restarting the core.
    (.inbounds[]
      | select(
          .tag=="vless-ws" or
          .tag=="vmess-ws" or
          .tag=="trojan-ws"
        )
      | .settings
    ) |= (
      .clients = (
        ((.clients // []) + (.users // []))
        | unique_by((.email // "") + "|" + (.id // .password // ""))
      )
      | del(.users)
    )
    |
    (.inbounds[]
      | select(
          .tag=="vless-ws" or
          .tag=="vmess-ws" or
          .tag=="trojan-ws"
        )
      | .streamSettings
    ) |= (
      .network = "ws"
      | del(.method)
      | .security = (.security // "none")
      | .wsSettings = (.wsSettings // {})
    )
  ' "$XRAY_CONFIG" >"$TMP"; then
    rm -f "$TMP"
    echo "Failed to repair Xray WebSocket transport."
    return 1
  fi

  if ! xray_test_file "$TMP"; then
    echo "Xray rejected the automatic WebSocket compatibility repair."
    [ -n "${XRAY_TEST_ERROR:-}" ] && printf '%s\n' "$XRAY_TEST_ERROR"
    rm -f "$TMP"
    return 1
  fi

  install -m 600 "$TMP" "$XRAY_CONFIG"
  rm -f "$TMP"
  chown root:root "$XRAY_CONFIG"
  return 0
}

xray_inbound_auth_schema_ok(){
  local TAG="$1"
  jq -e --arg tag "$TAG" '
    .inbounds[]?
    | select(.tag==$tag)
    | (
        (.settings.clients | type) == "array" and
        (.settings.clients | length) > 0 and
        ((.settings | has("users")) | not)
      )
  ' "$XRAY_CONFIG" >/dev/null 2>&1
}

nginx_ws_mapping_ok(){
  local FILE="$1" PATHX="$2" PORT="$3"
  python3 - "$FILE" "$PATHX" "$PORT" <<'PYMAP'
import re
import sys
from pathlib import Path

filename, ws_path, expected_port = sys.argv[1:]
try:
    content = Path(filename).read_text()
except OSError:
    raise SystemExit(1)

location = re.search(
    r'location\s*=\s*' + re.escape(ws_path) +
    r'\s*\{(?P<body>.*?)\n\s*\}',
    content,
    re.S,
)
if not location:
    raise SystemExit(1)

proxy = re.search(
    r'proxy_pass\s+http://127\.0\.0\.1:(\d+)\s*;',
    location.group("body"),
)
if not proxy or proxy.group(1) != expected_port:
    raise SystemExit(1)
PYMAP
}

mandatory_502_preinstall_fix(){
  local D="$1" ATTEMPT TAG PATHX PORT DIRECT_CODE PUBLIC_CODE FAILED
  local NGINX_FILE="/etc/nginx/conf.d/sultan-ready.conf"
  local VIA_WS=0

  current_session_via_ws && VIA_WS=1

  echo ""
  echo "==========================================="
  echo " Mandatory 502 Check - v27 Install Mode"
  echo "==========================================="

  for ATTEMPT in 1 2; do
    FAILED=0
    echo "Repair attempt: $ATTEMPT/2"

    # Xray may be restarted safely: the management SSH WebSocket is served
    # by sultan-ws, not by the Xray VLESS/VMess/Trojan inbounds.
    xray_force_ws_compat || return 1
    xray_restart_safe || return 1

    # Rebuild the proxy files. nginx_haproxy_restart_safe() preserves the
    # original v27 behavior: while connected through WebSocket, the live
    # reload is deferred until this SSH session has closed.
    refresh_proxy_config_from_current || return 1
    sleep 2

    for TAG in vless-ws vmess-ws trojan-ws; do
      PATHX="$(xray_current_path "$TAG" "$(xray_default_path "$TAG")")"
      PORT="$(jq -r --arg tag "$TAG" \
        '.inbounds[]? | select(.tag==$tag) | .port // empty' \
        "$XRAY_CONFIG" 2>/dev/null | head -n1)"

      if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "FAILED: $TAG has no valid backend port."
        FAILED=1
        continue
      fi

      if ! xray_inbound_auth_schema_ok "$TAG"; then
        echo "FAILED: $TAG accounts are not loaded from settings.clients."
        FAILED=1
        continue
      fi

      if ! wait_tcp_listener "$PORT"; then
        echo "FAILED: $TAG is not listening on 127.0.0.1:$PORT."
        FAILED=1
        continue
      fi

      # Mandatory static mapping check prevents:
      # /vless path -> VMess port, or any other cause of Nginx HTTP 502.
      if ! nginx_ws_mapping_ok "$NGINX_FILE" "$PATHX" "$PORT"; then
        echo "FAILED: Nginx mapping for $PATHX is not using port $PORT."
        FAILED=1
        continue
      fi

      # This is the mandatory backend proof. Xray must perform a real
      # WebSocket upgrade and return HTTP 101 before installation succeeds.
      DIRECT_CODE="$(direct_websocket_status_code "$PORT" "$PATHX" "$D")"

      printf "%-10s path=%-22s port=%-6s direct=%-3s" \
        "$TAG" "$PATHX" "$PORT" "${DIRECT_CODE:-000}"

      if [ "$DIRECT_CODE" != "101" ]; then
        echo "  FAILED"
        FAILED=1
        continue
      fi

      if [ "$VIA_WS" -eq 1 ]; then
        # Do not test the live 443 route yet: v27 intentionally leaves the
        # current Nginx/HAProxy workers untouched until this SSH session ends.
        echo "  public=deferred"
      else
        PUBLIC_CODE="$(websocket_status_code "$D" "$PATHX")"
        printf " public=%-3s" "${PUBLIC_CODE:-000}"
        if [ "$PUBLIC_CODE" != "101" ]; then
          echo "  FAILED"
          FAILED=1
        else
          echo "  OK"
        fi
      fi
    done

    if [ "$FAILED" -eq 0 ]; then
      if [ "$VIA_WS" -eq 1 ]; then
        # Proxy reload was already queued by nginx_haproxy_restart_safe().
        # Queue a diagnostic after logout, without touching this connection.
        defer_command_until_logout "502-postcheck" \
          "sleep 5; /usr/local/bin/menu --health-check >/var/log/sultan-502-postcheck.log 2>&1 || true" \
          || true
        echo ""
        echo "Mandatory direct HTTP 101 checks passed."
        echo "Nginx path-to-port mappings passed."
        echo "Public 443 reload/test is deferred until logout to preserve this SSH session."
      else
        echo ""
        echo "Mandatory direct and public HTTP 101 checks passed."
      fi
      return 0
    fi

    if [ "$ATTEMPT" -eq 1 ]; then
      echo "A WebSocket backend failed. Rebuilding only Xray/proxy configuration..."
      create_xray_config --quiet || return 1
      refresh_proxy_config_from_current || return 1
      sleep 2
    fi
  done

  echo ""
  echo "INSTALLATION BLOCKED: mandatory 502 prevention failed."
  echo "The installer will not report success."
  echo ""
  echo "Xray transports:"
  jq -r '
    .inbounds[]? |
    select(.tag=="vless-ws" or .tag=="vmess-ws" or .tag=="trojan-ws") |
    "\(.tag) network=\(.streamSettings.network // "-") method=\(.streamSettings.method // "-") port=\(.port) path=\(.streamSettings.wsSettings.path // "-")"
  ' "$XRAY_CONFIG" 2>/dev/null || true
  echo ""
  echo "Recent Xray log:"
  journalctl -u xray -n 40 --no-pager 2>/dev/null || true
  return 1
}

vmess_end_to_end_test(){
  local D="$1" VMESS_ID VMESS_PATH SOCKS_PORT HTTP_PORT TMPDIR CLIENT_CFG CLIENT_LOG HTTP_PID XRAY_PID RESULT TRY
  VMESS_ID="$(jq -r '.inbounds[] | select(.tag=="vmess-ws") | .settings.clients[]? | select(.email=="_sultan_placeholder_vmess") | .id' "$XRAY_CONFIG" 2>/dev/null | head -n1)"
  VMESS_PATH="$(xray_current_path vmess-ws /vmess-ws)"
  [ -n "$VMESS_ID" ] && [ "$VMESS_ID" != "null" ] || {
    echo "VMess internal test credential is missing."
    return 1
  }

  SOCKS_PORT="$(python3 - <<'PYPORT'
import socket
s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()
PYPORT
)"
  HTTP_PORT="$(python3 - <<'PYPORT'
import socket
s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()
PYPORT
)"
  [[ "$SOCKS_PORT" =~ ^[0-9]+$ ]] || return 1
  [[ "$HTTP_PORT" =~ ^[0-9]+$ ]] || return 1

  TMPDIR="$(mktemp -d /tmp/sultan-vmess-test.XXXXXX)" || return 1
  CLIENT_CFG="$TMPDIR/client.json"
  CLIENT_LOG="$TMPDIR/client.log"

  cat >"$CLIENT_CFG" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "listen": "127.0.0.1",
    "port": $SOCKS_PORT,
    "protocol": "socks",
    "settings": {"auth": "noauth", "udp": false}
  }],
  "outbounds": [{
    "protocol": "vmess",
    "settings": {"vnext": [{
      "address": "127.0.0.1",
      "port": 443,
      "users": [{"id": "$VMESS_ID", "security": "auto"}]
    }]},
    "streamSettings": {
      "network": "ws",
      "security": "tls",
      "tlsSettings": {"serverName": "$D", "allowInsecure": true},
      "wsSettings": {"path": "$VMESS_PATH", "headers": {"Host": "$D"}}
    }
  }]
}
EOF

  xray_test_file "$CLIENT_CFG" || {
    echo "VMess client self-test config is invalid."
    rm -rf "$TMPDIR"
    return 1
  }

  python3 - "$HTTP_PORT" <<'PYHTTP' >"$TMPDIR/http.log" 2>&1 &
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
port=int(sys.argv[1])
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body=b"SULTAN-V2RAY-OK"
        self.send_response(200)
        self.send_header("Content-Type","text/plain")
        self.send_header("Content-Length",str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, fmt, *args):
        pass
HTTPServer(("127.0.0.1",port),Handler).handle_request()
PYHTTP
  HTTP_PID=$!

  xray run -config "$CLIENT_CFG" >"$CLIENT_LOG" 2>&1 &
  XRAY_PID=$!

  for TRY in {1..15}; do
    ss -H -ltn "sport = :$SOCKS_PORT" 2>/dev/null | grep -q . && break
    kill -0 "$XRAY_PID" 2>/dev/null || break
    sleep 1
  done

  RESULT="$(curl -fsS --max-time 10 --socks5-hostname "127.0.0.1:$SOCKS_PORT" "http://127.0.0.1:$HTTP_PORT/health" 2>/dev/null || true)"

  kill "$XRAY_PID" "$HTTP_PID" 2>/dev/null || true
  wait "$XRAY_PID" 2>/dev/null || true
  wait "$HTTP_PID" 2>/dev/null || true

  if [ "$RESULT" = "SULTAN-V2RAY-OK" ]; then
    echo "VMess WebSocket end-to-end tunnel verified."
    rm -rf "$TMPDIR"
    return 0
  fi

  echo "VMess WebSocket end-to-end tunnel failed."
  cat "$CLIENT_LOG" 2>/dev/null || true
  rm -rf "$TMPDIR"
  return 1
}


vless_end_to_end_test(){
  local D="$1" VLESS_ID="$2" VLESS_PATH="$3" SOCKS_PORT HTTP_PORT TMPDIR CLIENT_CFG CLIENT_LOG HTTP_PID XRAY_PID RESULT TRY BIN
  [ -n "$D" ] && validate_domain "$D" || { echo "VLESS test domain is invalid."; return 1; }
  [ -n "$VLESS_ID" ] || { echo "VLESS test ID is missing."; return 1; }
  validate_ws_path "$VLESS_PATH" || { echo "VLESS test path is invalid."; return 1; }
  BIN="$(xray_binary 2>/dev/null || true)"
  [ -n "$BIN" ] || { echo "Xray binary is missing."; return 1; }

  SOCKS_PORT="$(python3 - <<'PYPORT'
import socket
s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()
PYPORT
)"
  HTTP_PORT="$(python3 - <<'PYPORT'
import socket
s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()
PYPORT
)"
  [[ "$SOCKS_PORT" =~ ^[0-9]+$ ]] || return 1
  [[ "$HTTP_PORT" =~ ^[0-9]+$ ]] || return 1

  TMPDIR="$(mktemp -d /tmp/sultan-vless-test.XXXXXX)" || return 1
  CLIENT_CFG="$TMPDIR/client.json"
  CLIENT_LOG="$TMPDIR/client.log"

  cat >"$CLIENT_CFG" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "listen": "127.0.0.1",
    "port": $SOCKS_PORT,
    "protocol": "socks",
    "settings": {"auth": "noauth", "udp": false}
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "address": "127.0.0.1",
      "port": 443,
      "id": "$VLESS_ID",
      "encryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "security": "tls",
      "tlsSettings": {"serverName": "$D", "allowInsecure": true},
      "wsSettings": {"path": "$VLESS_PATH", "host": "$D"}
    }
  }]
}
EOF

  if ! xray_test_file "$CLIENT_CFG"; then
    echo "VLESS client self-test config is invalid."
    [ -n "${XRAY_TEST_ERROR:-}" ] && printf '%s\n' "$XRAY_TEST_ERROR"
    rm -rf "$TMPDIR"
    return 1
  fi

  python3 - "$HTTP_PORT" <<'PYHTTP' >"$TMPDIR/http.log" 2>&1 &
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
port=int(sys.argv[1])
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body=b"SULTAN-VLESS-OK"
        self.send_response(200)
        self.send_header("Content-Type","text/plain")
        self.send_header("Content-Length",str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, fmt, *args):
        pass
HTTPServer(("127.0.0.1",port),Handler).handle_request()
PYHTTP
  HTTP_PID=$!

  "$BIN" run -config "$CLIENT_CFG" >"$CLIENT_LOG" 2>&1 &
  XRAY_PID=$!

  for TRY in {1..15}; do
    ss -H -ltn "sport = :$SOCKS_PORT" 2>/dev/null | grep -q . && break
    kill -0 "$XRAY_PID" 2>/dev/null || break
    sleep 1
  done

  RESULT="$(curl -fsS --max-time 12 --socks5-hostname "127.0.0.1:$SOCKS_PORT" "http://127.0.0.1:$HTTP_PORT/health" 2>/dev/null || true)"

  kill "$XRAY_PID" "$HTTP_PID" 2>/dev/null || true
  wait "$XRAY_PID" 2>/dev/null || true
  wait "$HTTP_PID" 2>/dev/null || true

  if [ "$RESULT" = "SULTAN-VLESS-OK" ]; then
    echo "VLESS WebSocket end-to-end tunnel verified."
    rm -rf "$TMPDIR"
    return 0
  fi

  echo "VLESS WebSocket end-to-end tunnel failed."
  cat "$CLIENT_LOG" 2>/dev/null || true
  echo "Recent server log:"
  journalctl -u xray -n 15 --no-pager 2>/dev/null || true
  rm -rf "$TMPDIR"
  return 1
}

v2ray_ws_self_test(){
  local D="$1" TAG PATHX PORT CODE FAILED=0 VLESS_ID
  [ -n "$D" ] && [ "$D" != "Not Set" ] || { echo "Domain is not set."; return 1; }
  validate_domain "$D" || { echo "Domain is invalid: $D"; return 1; }

  xray_config_ok || { echo "Xray configuration test failed."; return 1; }
  refresh_proxy_config_from_current || { echo "Proxy synchronization failed."; return 1; }
  nginx -t >/dev/null 2>&1 || { echo "Nginx configuration test failed."; return 1; }
  haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1 || { echo "HAProxy configuration test failed."; return 1; }

  wait_service_active xray || FAILED=1
  wait_service_active nginx || FAILED=1
  wait_service_active haproxy || FAILED=1
  wait_tcp_listener 443 || FAILED=1

  for TAG in vless-ws vmess-ws trojan-ws; do
    PATHX="$(xray_current_path "$TAG" "$(xray_default_path "$TAG")")"
    case "$TAG" in
      vless-ws) PORT=10000 ;;
      vmess-ws) PORT=10085 ;;
      trojan-ws) PORT=10086 ;;
    esac
    wait_tcp_listener "$PORT" || { FAILED=1; continue; }
    CODE="$(websocket_status_code "$D" "$PATHX")"
    if [ "$CODE" != "101" ]; then
      echo "WebSocket verification failed: $PATHX returned HTTP ${CODE:-000}."
      FAILED=1
    else
      echo "WebSocket verified: $PATHX -> 127.0.0.1:$PORT"
    fi
  done

  echo "VLESS/VMess/Trojan WebSocket route checks completed with HTTP 101."

  [ "$FAILED" -eq 0 ] || {
    echo "Recent Xray log:"
    journalctl -u xray -n 20 --no-pager 2>/dev/null || true
    echo "Recent Nginx log:"
    journalctl -u nginx -n 20 --no-pager 2>/dev/null || true
    return 1
  }
  return 0
}

v2ray_ws_verify_or_repair(){
  local D="$1"
  if v2ray_ws_self_test "$D"; then
    return 0
  fi

  echo "V2Ray WebSocket test failed. Running one automatic repair..."
  create_xray_config --quiet || return 1
  xray_restart_safe || return 1
  nginx_haproxy_restart_safe || return 1
  sleep 2
  v2ray_ws_self_test "$D"
}

full_install_self_test(){
  local D="$1" SERVICE FAILED=0
  for SERVICE in sultan-ws udp-custom xray nginx haproxy fail2ban sultan-quota.timer; do
    wait_service_active "$SERVICE" || FAILED=1
  done
  if ! systemctl is-active --quiet ssh 2>/dev/null && ! systemctl is-active --quiet sshd 2>/dev/null; then
    echo "SSH service is not active."
    FAILED=1
  fi
  safe_restart_ssh || FAILED=1
  fail2ban-client ping 2>/dev/null | grep -q 'pong' || {
    echo "Fail2Ban did not answer ping."
    FAILED=1
  }
  SSH_WS_CODE="$(websocket_status_code "$D" "/")"
  if [ "$SSH_WS_CODE" != "101" ]; then
    echo "Legacy SSH WebSocket path / failed with HTTP ${SSH_WS_CODE:-000}."
    FAILED=1
  else
    echo "Legacy SSH WebSocket path / verified."
  fi
  v2ray_ws_verify_or_repair "$D" || FAILED=1
  [ "$FAILED" -eq 0 ]
}

setup_ready(){
  refresh_screen
  local D ND CERT KEY WS_TOKEN
  D="$(get_domain)"
  [ "$D" = "Not Set" ] && D=""
  echo "Current Domain: ${D:-Not Set}"
  ND=""
  if [ -r /dev/tty ]; then
    read -r -p "Domain [press Enter to keep current]: " ND </dev/tty || true
  else
    read -r -p "Domain [press Enter to keep current]: " ND || true
  fi
  [ -n "$ND" ] && D="$ND"
  [ -n "$D" ] || { echo "Domain required"; pause; return 1; }
  validate_domain "$D" || { echo "Invalid domain format."; pause; return 1; }
  echo "$D" > "$DOMAIN_FILE"
  chmod 600 "$DOMAIN_FILE"

  open_main_ports || { echo "Firewall setup failed."; pause; return 1; }

  install_ws || { pause; return 1; }
  install_udp || { pause; return 1; }
  install_xray --quiet || { echo "Xray install failed."; pause; return 1; }
  create_xray_config --quiet || { echo "Xray WebSocket config creation failed."; pause; return 1; }
  ensure_xray_config || { echo "Xray config is invalid."; pause; return 1; }
  WS_TOKEN="$(ensure_ws_token)"

  [ -f "/etc/letsencrypt/live/$D/fullchain.pem" ] || create_self_signed_cert "$D"

  if [ -f "/etc/letsencrypt/live/$D/fullchain.pem" ]; then
    CERT="/etc/letsencrypt/live/$D/fullchain.pem"
    KEY="/etc/letsencrypt/live/$D/privkey.pem"
  else
    CERT="/etc/sultan/selfsigned/$D/fullchain.pem"
    KEY="/etc/sultan/selfsigned/$D/privkey.pem"
  fi

  write_nginx_config "$D" "$CERT" "$KEY" "$WS_TOKEN"
  write_haproxy_config

  nginx -t || { echo "Nginx config error."; pause; return 1; }
  haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null || { echo "HAProxy config error."; pause; return 1; }
  safe_restart_ssh || { pause; return 1; }
  xray_restart_safe || { pause; return 1; }
  nginx_haproxy_restart_safe || { pause; return 1; }

  if [ ! -f "/etc/letsencrypt/live/$D/fullchain.pem" ]; then
    if certbot certonly --webroot -w /var/www/sultan-acme -d "$D" --cert-name "$D" \
      --agree-tos -m "admin@$D" --non-interactive; then
      CERT="/etc/letsencrypt/live/$D/fullchain.pem"
      KEY="/etc/letsencrypt/live/$D/privkey.pem"
      write_nginx_config "$D" "$CERT" "$KEY" "$WS_TOKEN"
      nginx -t || { echo "Nginx config failed after certificate installation."; pause; return 1; }
      if current_session_via_ws; then
        defer_command_until_logout "cert-nginx-reload"           "nginx -t && systemctl reload nginx" || true
        echo "Certificate installed; Nginx reload was deferred until logout to protect this SSH session."
      else
        systemctl reload nginx || { echo "Nginx reload failed after certificate installation."; pause; return 1; }
      fi
    else
      echo "Let's Encrypt failed; self-signed certificate is active."
    fi
  fi

  mkdir -p /etc/letsencrypt/renewal-hooks/deploy
  cat >/etc/letsencrypt/renewal-hooks/deploy/sultan-reload.sh <<'RENEW_HOOK'
#!/bin/sh
nginx -t && systemctl reload nginx
RENEW_HOOK
  chmod 700 /etc/letsencrypt/renewal-hooks/deploy/sultan-reload.sh

  # This is mandatory and safe for the current SSH session: Xray is restarted,
  # while Nginx/HAProxy use validated graceful reloads. Installation cannot
  # complete while any Xray WebSocket route returns HTTP 502/non-101.
  if ! mandatory_502_preinstall_fix "$D"; then
    echo "Ready setup stopped because the mandatory 502 check failed."
    pause
    return 1
  fi

  if current_session_via_ws; then
    echo "Current SSH session is using the old WebSocket login path."
    echo "Mandatory backend HTTP 101 verification passed; v27-style proxy reload/public test was deferred."
    echo "After you close this SSH session, reconnect and run: menu -> 18 -> 5 Full WebSocket Test"
  else
    echo "Running complete installation test..."
    if ! full_install_self_test "$D"; then
      echo "Installation verification failed. Review the errors above."
      pause
      return 1
    fi
  fi

  echo "Ready setup completed"
  echo "SSH WS Path: / (old legacy compatible)"
  echo "V2Ray WS Paths: $(xray_current_path vless-ws /vless-ws) $(xray_current_path vmess-ws /vmess-ws) $(xray_current_path trojan-ws /trojan-ws)"
  pause
}

setting_menu(){
  while true; do
    refresh_screen
    echo "[1] Setup Domain + SSL + WS + V2Ray"
    echo "[2] Restart All Services"
    echo "[3] Open Main Ports"
    echo "[4] Force Quota Check"
    echo "[5] Reset User Traffic"
    echo "[10] Service Control"
    echo "[0] Back"
    read -p "Select: " s
    case "$s" in
      1) setup_ready ;;
      2)
        safe_restart_ssh || { pause; continue; }
        nginx_haproxy_restart_safe || { pause; continue; }
        if current_session_via_ws && systemctl is-active --quiet sultan-ws 2>/dev/null; then
          echo "Skipped WebSocket restart to protect this SSH session."
        else
          checked_restart sultan-ws || { pause; continue; }
        fi
        checked_restart udp-custom || { pause; continue; }
        xray_restart_safe || { pause; continue; }
        checked_restart fail2ban || { pause; continue; }
        echo "Services restarted."
        pause
        ;;
      3) open_main_ports; pause ;;
      4) quota_sync; echo "Quota checked"; pause ;;
      5)
        read -p "Username: " U
        usage_reset_user "$U" || { echo "Traffic reset failed"; pause; continue; }
        quota_sync
        echo "Traffic reset for $U"
        pause
        ;;
      10) service_control_menu ;;
      0) return ;;
    esac
  done
}

udp_menu(){
  refresh_screen
  echo "[1] Install/Reinstall UDP 7300"
  echo "[2] Disable UDP"
  echo "[0] Back"
  read -p "Select: " u
  case "$u" in
    1) install_udp; pause ;;
    2) systemctl disable --now udp-custom 2>/dev/null || true; pause ;;
  esac
}

domain_menu(){
  while true; do
    refresh_screen
    CURRENT="$(get_domain)"
    echo "==================================="
    echo "            DOMAIN MENU"
    echo "==================================="
    box "Current Domain" "$CURRENT"
    echo "[1] Show Domain"
    echo "[2] Change Domain"
    echo "[3] Setup Domain + SSL + WS + V2Ray"
    echo "[0] Back"
    read -p "Select: " d

    case "$d" in
      1) refresh_screen; box "Current Domain" "$(get_domain)"; pause ;;
      2)
        refresh_screen
        box "Current Domain" "$(get_domain)"
        read -p "New domain: " D
        if [ -n "$D" ]; then
          validate_domain "$D" || { echo "Invalid domain format."; pause; continue; }
          echo "$D" > "$DOMAIN_FILE"
          chmod 600 "$DOMAIN_FILE"
        fi
        box "Saved Domain" "$(get_domain)"
        pause
        ;;
      3) setup_ready ;;
      0) return ;;
    esac
  done
}

ssl_menu(){
  refresh_screen
  echo "[1] Install/Setup SSL"
  echo "[2] Renew SSL"
  echo "[3] Check SSL"
  read -p "Select: " s
  case "$s" in
    1) setup_ready ;;
    2) certbot renew --deploy-hook "systemctl reload nginx haproxy"; pause ;;
    3) box "TLS" "$(tls_status)"; pause ;;
  esac
}

write_sultan_fail2ban_jail(){
  local CLIENT_IP="${SSH_CONNECTION%% *}"
  case "$CLIENT_IP" in
    ''|*[!0-9a-fA-F:.]*) CLIENT_IP="" ;;
  esac
  mkdir -p /etc/fail2ban/jail.d
  cat >/etc/fail2ban/jail.d/sultan-sshd.conf <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
ignoreip = 127.0.0.1/8 ::1 $CLIENT_IP
EOF
}

install_fail2ban_sultan(){
  refresh_screen
  echo "========================================"
  echo "          FAIL2BAN REINSTALL"
  echo "========================================"
  apt update -y
  apt install -y --reinstall fail2ban

  write_sultan_fail2ban_jail

  systemctl daemon-reload
  systemctl enable fail2ban >/dev/null 2>&1 || true
  checked_restart fail2ban || { pause; return; }

  echo "----------------------------------------"
  systemctl is-active --quiet fail2ban && echo "Fail2Ban reinstalled." || echo "Fail2Ban failed."
  echo "========================================"
  pause
}

remove_fail2ban_sultan(){
  refresh_screen
  echo "========================================"
  echo "            REMOVE FAIL2BAN"
  echo "========================================"
  read -p "Type YES to remove Fail2Ban: " C
  C="$(echo "$C" | tr '[:lower:]' '[:upper:]')"
  [ "$C" = "YES" ] || { echo "Cancelled."; pause; return; }

  systemctl disable --now fail2ban 2>/dev/null || true
  apt purge -y fail2ban 2>/dev/null || apt remove -y fail2ban 2>/dev/null || true
  rm -rf /etc/fail2ban
  systemctl daemon-reload

  echo "Fail2Ban removed."
  pause
}

fail2ban_menu(){
  while true; do
    refresh_screen
    echo "[1] Reinstall Fail2Ban"
    echo "[2] Remove Fail2Ban"
    echo "[0] Back"
    read -p "Select: " f
    case "$f" in
      1) install_fail2ban_sultan ;;
      2) remove_fail2ban_sultan ;;
      0) return ;;
    esac
  done
}

install_bbr_sultan(){
  refresh_screen
  echo "========================================"
  echo "             BBR REINSTALL"
  echo "========================================"

  modprobe tcp_bbr 2>/dev/null || true
  cat >/etc/sysctl.d/99-sultan-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

  sysctl -p /etc/sysctl.d/99-sultan-bbr.conf || sysctl --system || true

  echo "----------------------------------------"
  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -qw bbr; then
    echo "BBR reinstalled."
  else
    echo "BBR failed. Kernel may not support BBR."
  fi
  echo "========================================"
  pause
}

remove_bbr_sultan(){
  refresh_screen
  echo "========================================"
  echo "              REMOVE BBR"
  echo "========================================"
  read -p "Type YES to remove BBR: " C
  C="$(echo "$C" | tr '[:lower:]' '[:upper:]')"
  [ "$C" = "YES" ] || { echo "Cancelled."; pause; return; }

  rm -f /etc/sysctl.d/99-sultan-bbr.conf
  sed -i '/net.core.default_qdisc=fq/d;/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf 2>/dev/null || true

  if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw cubic; then
    sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
  fi
  sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1 || true
  sysctl --system >/dev/null 2>&1 || true

  echo "BBR removed."
  pause
}

bbr_menu(){
  while true; do
    refresh_screen
    echo "[1] Reinstall BBR"
    echo "[2] Remove BBR"
    echo "[0] Back"
    read -p "Select: " b
    case "$b" in
      1) install_bbr_sultan ;;
      2) remove_bbr_sultan ;;
      0) return ;;
    esac
  done
}

vps_info(){
  refresh_screen
  box "OS" "$(get_os)"
  box "Kernel" "$(get_kernel)"
  box "IP Address" "$(get_ip)"
  box "Uptime" "$(get_uptime)"
  box "RAM Usage" "$(get_ram)"
  box "Disk Usage" "$(get_disk)"
  pause
}

online_users_menu(){
  refresh_screen
  echo "========================================"
  echo "             ONLINE USERS"
  echo "========================================"

  local FOUND=0 N=1 U PID IP LIMIT ACTIVE DIR SLOT SAVED_START CURRENT_START CMD
  while IFS='|' read -r U _ _ _ LIMIT; do
    [ -n "$U" ] || continue
    id "$U" >/dev/null 2>&1 || continue

    ACTIVE="$(active_user_logins "$U")"
    [ "$ACTIVE" -gt 0 ] || continue
    FOUND=1

    case "$LIMIT" in
      ""|0|Unlimited|unlimited|UNLIMITED) LIMIT_TEXT="Unlimited" ;;
      *) LIMIT_TEXT="$LIMIT" ;;
    esac

    echo ""
    printf "%s\n" "$U"
    printf "Online Users : %s/%s\n" "$ACTIVE" "$LIMIT_TEXT"

    DIR="/run/sultan-login-slots/$U"
    shopt -s nullglob
    for SLOT in "$DIR"/*; do
      PID="${SLOT##*/}"
      [[ "$PID" =~ ^[0-9]+$ ]] || continue
      [ -d "/proc/$PID" ] || continue
      CMD="$(cat "/proc/$PID/comm" 2>/dev/null || true)"
      SAVED_START="$(awk -F= '$1=="start"{print $2;exit}' "$SLOT" 2>/dev/null || true)"
      CURRENT_START="$(awk '{print $22}' "/proc/$PID/stat" 2>/dev/null || true)"
      [ "$CMD" = "sshd" ] || continue
      [ -n "$SAVED_START" ] && [ "$SAVED_START" = "$CURRENT_START" ] || continue

      IP="$(awk -F= '$1=="rhost"{print $2;exit}' "$SLOT" 2>/dev/null || true)"
      [ -n "$IP" ] || IP="Unknown"

      printf "\n(%d) SSH Device\n" "$N"
      printf "%-8s: %s\n" "IP" "$IP"
      printf "%-8s: Active\n" "Login"
      N=$((N+1))
    done
    shopt -u nullglob
  done < "$DB"

  [ "$FOUND" = "1" ] || echo "No SSH users online."
  echo ""
  echo "========================================"
  pause
}

backup_menu(){
  refresh_screen
  echo "[1] Create Backup"
  echo "[2] Restore Backup"
  read -p "Select: " b
  case "$b" in
    1)
      mkdir -p /root/sultan-backup
      BP="/root/sultan-backup/sultan-$(date +%F-%H%M).tar.gz"
      tar -czf "$BP" \
        /etc/sultan /usr/local/etc/xray /usr/local/bin/menu \
        /usr/local/bin/sultan-ssh-ws /usr/local/bin/sultan-udp-relay \
        /usr/local/sbin/sultan-login-limit /usr/local/sbin/sultan-quota-sync /usr/local/sbin/sultan-tunnel-shell \
        /etc/systemd/system/sultan-ws.service /etc/systemd/system/udp-custom.service \
        /etc/systemd/system/sultan-quota.service /etc/systemd/system/sultan-quota.timer \
        /etc/nginx/conf.d/sultan-ready.conf /etc/haproxy/haproxy.cfg \
        /etc/ssh/sshd_config.d/98-sultan-legacy-login.conf /etc/ssh/sshd_config.d/99-sultan-users.conf /etc/fail2ban/jail.d/sultan-sshd.conf \
        /etc/sysctl.d/99-sultan-bbr.conf 2>/dev/null ||
        { echo "Backup failed."; pause; return; }
      chmod 600 "$BP"
      echo "Backup created: $BP"
      pause
      ;;
    2)
      read -p "Backup path: " BP
      [ -f "$BP" ] || { echo "Backup file not found."; pause; return; }
      tar -tzf "$BP" >/dev/null || { echo "Invalid backup archive."; pause; return; }
      tar -xzf "$BP" -C / || { echo "Restore failed."; pause; return; }
      systemctl daemon-reload
      quota_sync
      echo "Restore completed. Review services before production use."
      pause
      ;;
  esac
}

bot_menu(){
  refresh_screen
  echo "[1] Save Bot Token"
  echo "[2] Save Chat ID"
  echo "[3] Test Message"
  read -p "Select: " b
  case "$b" in
    1) read -r -s -p "Bot Token: " T; echo ""; printf '%s\n' "$T" > "$BASE/bot_token"; chmod 600 "$BASE/bot_token" ;;
    2) read -p "Chat ID: " C; printf '%s\n' "$C" > "$BASE/chat_id"; chmod 600 "$BASE/chat_id" ;;
    3)
      T="$(cat "$BASE/bot_token" 2>/dev/null)"
      C="$(cat "$BASE/chat_id" 2>/dev/null)"
      [ -n "$T" ] && [ -n "$C" ] || { echo "Token or Chat ID missing."; pause; return; }
      curl -fsS "https://api.telegram.org/bot$T/sendMessage" -d chat_id="$C" -d text="SULTAN Panel Test"
      ;;
  esac
  pause
}

confirm_service_action(){
  local MSG="$1" C
  echo "$MSG"
  read -p "Type YES to continue: " C
  [ "$C" = "YES" ]
}

service_unit_exists(){
  local S="$1"
  systemctl cat "$S.service" >/dev/null 2>&1 || systemctl cat "$S" >/dev/null 2>&1
}

service_control_menu(){
  while true; do
    refresh_screen
    echo "========================================"
    echo "          SERVICE CONTROL MENU"
    echo "========================================"
    echo "[1]  Nginx Menu"
    echo "[2]  HAProxy Menu"
    echo "[3]  UDP Menu"
    echo "[4]  WebSocket Menu"
    echo "[5]  SSL/TLS Menu"
    echo "[6]  BBR Menu"
    echo "[7]  Fail2Ban Menu"
    echo "[8]  Port Menu"
    echo "[9]  Xray Menu"
    echo "[10] Restart All Server"
    echo "[0]  Back"
    echo "========================================"
    read -p "Select: " sc
    case "$sc" in
      1) service_item_menu "Nginx" nginx ;;
      2) service_item_menu "HAProxy" haproxy ;;
      3) service_item_menu "UDP" udp ;;
      4) service_item_menu "WebSocket" websocket ;;
      5) service_item_menu "SSL/TLS" ssltls ;;
      6) service_item_menu "BBR" bbr ;;
      7) service_item_menu "Fail2Ban" fail2ban ;;
      8) service_item_menu "Port" port ;;
      9) service_item_menu "Xray" xray ;;
      10) reinstall_all_server_mini ;;
      0) return ;;
      *) echo "Invalid option"; sleep 1 ;;
    esac
  done
}

service_item_menu(){
  local TITLE="$1" KEY="$2" A
  while true; do
    refresh_screen
    echo "========================================"
    echo "              $TITLE MENU"
    echo "========================================"
    echo "[1] Stop"
    echo "[2] Reinstall"
    echo "[3] Delete"
    echo "[0] Back"
    echo "========================================"
    read -p "Select: " A
    case "$A" in
      1) service_stop_action "$KEY"; pause ;;
      2) service_reinstall_action "$KEY"; pause ;;
      3) service_delete_action "$KEY"; pause ;;
      0) return ;;
      *) echo "Invalid option"; sleep 1 ;;
    esac
  done
}

service_stop_action(){
  local KEY="$1"
  refresh_screen
  case "$KEY" in
    nginx)
      echo "Stopping Nginx..."
      if current_session_via_ws; then
        confirm_service_action "Stopping Nginx may disconnect your current WebSocket SSH session." || { echo "Cancelled."; return; }
      fi
      systemctl stop nginx 2>/dev/null || true
      systemctl status nginx --no-pager -l 2>/dev/null || true
      ;;
    haproxy)
      echo "Stopping HAProxy..."
      if current_session_via_ws; then
        confirm_service_action "Stopping HAProxy may disconnect your current WebSocket SSH session." || { echo "Cancelled."; return; }
      fi
      systemctl stop haproxy 2>/dev/null || true
      systemctl status haproxy --no-pager -l 2>/dev/null || true
      ;;
    udp)
      echo "Stopping UDP Custom..."
      systemctl stop udp-custom 2>/dev/null || true
      systemctl status udp-custom --no-pager -l 2>/dev/null || true
      ;;
    websocket)
      echo "Stopping WebSocket..."
      if current_session_via_ws; then
        confirm_service_action "Stopping WebSocket may disconnect your current SSH session." || { echo "Cancelled."; return; }
      fi
      systemctl stop sultan-ws 2>/dev/null || true
      systemctl status sultan-ws --no-pager -l 2>/dev/null || true
      ;;
    ssltls)
      confirm_service_action "Stopping SSL/TLS endpoint will stop Nginx and HAProxy. This can disconnect clients." || { echo "Cancelled."; return; }
      systemctl stop haproxy 2>/dev/null || true
      systemctl stop nginx 2>/dev/null || true
      echo "SSL/TLS endpoint stopped."
      ;;
    bbr)
      echo "Disabling BBR..."
      rm -f /etc/sysctl.d/99-sultan-bbr.conf
      sed -i '/net.core.default_qdisc=fq/d;/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf 2>/dev/null || true
      if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw cubic; then
        sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
      fi
      sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1 || true
      sysctl --system >/dev/null 2>&1 || true
      echo "BBR stopped/disabled."
      ;;
    fail2ban)
      echo "Stopping Fail2Ban..."
      systemctl stop fail2ban 2>/dev/null || true
      systemctl status fail2ban --no-pager -l 2>/dev/null || true
      ;;
    port)
      confirm_service_action "This will close public VPN ports in UFW rules. SSH port will not be touched." || { echo "Cancelled."; return; }
      if command -v ufw >/dev/null 2>&1; then
        for P in 80/tcp 443/tcp 8080/tcp 7300/udp; do
          ufw delete allow "$P" >/dev/null 2>&1 || true
          ufw deny "$P" >/dev/null 2>&1 || true
        done
        ufw reload >/dev/null 2>&1 || true
        ufw status verbose || true
      else
        echo "UFW is not installed."
      fi
      ;;
    xray)
      echo "Stopping Xray..."
      systemctl stop xray 2>/dev/null || true
      systemctl status xray --no-pager -l 2>/dev/null || true
      ;;
  esac
}

service_reinstall_action(){
  local KEY="$1" D FILES CERT KEYFILE TOKEN
  refresh_screen
  case "$KEY" in
    nginx)
      echo "Reinstalling Nginx..."
      apt-get update -y
      apt-get install -y --reinstall nginx
      if validate_domain "$(get_domain)"; then
        refresh_proxy_config_from_current || true
      else
        nginx -t && checked_restart nginx || true
      fi
      systemctl status nginx --no-pager -l 2>/dev/null || true
      ;;
    haproxy)
      echo "Reinstalling HAProxy..."
      apt-get update -y
      apt-get install -y --reinstall haproxy
      if validate_domain "$(get_domain)"; then
        refresh_proxy_config_from_current || true
      else
        haproxy -c -f /etc/haproxy/haproxy.cfg && checked_restart haproxy || true
      fi
      systemctl status haproxy --no-pager -l 2>/dev/null || true
      ;;
    udp)
      echo "Reinstalling UDP Custom..."
      install_udp
      systemctl status udp-custom --no-pager -l 2>/dev/null || true
      ;;
    websocket)
      echo "Reinstalling WebSocket..."
      install_ws
      systemctl status sultan-ws --no-pager -l 2>/dev/null || true
      ;;
    ssltls)
      echo "Reinstalling SSL/TLS setup..."
      setup_ready
      ;;
    bbr)
      echo "Reinstalling BBR..."
      modprobe tcp_bbr 2>/dev/null || true
      cat >/etc/sysctl.d/99-sultan-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
      sysctl -p /etc/sysctl.d/99-sultan-bbr.conf || sysctl --system || true
      sysctl net.ipv4.tcp_congestion_control 2>/dev/null || true
      ;;
    fail2ban)
      echo "Reinstalling Fail2Ban..."
      apt-get update -y
      apt-get install -y --reinstall fail2ban
      write_sultan_fail2ban_jail
      systemctl daemon-reload
      systemctl enable fail2ban >/dev/null 2>&1 || true
      checked_restart fail2ban || true
      systemctl status fail2ban --no-pager -l 2>/dev/null || true
      ;;
    port)
      echo "Opening main ports..."
      open_main_ports
      ufw status verbose 2>/dev/null || true
      ;;
    xray)
      echo "Reinstalling Xray..."
      install_xray --quiet || true
      create_xray_config --quiet || true
      xray_restart_safe || true
      systemctl status xray --no-pager -l 2>/dev/null || true
      ;;
  esac
}

service_delete_action(){
  local KEY="$1" D
  refresh_screen
  case "$KEY" in
    nginx)
      confirm_service_action "Delete Nginx completely? This can stop all TLS/WebSocket traffic." || { echo "Cancelled."; return; }
      systemctl disable --now nginx 2>/dev/null || true
      apt-get purge -y nginx nginx-common nginx-core nginx-full 2>/dev/null || apt-get remove -y nginx 2>/dev/null || true
      rm -rf /etc/nginx
      systemctl daemon-reload
      echo "Nginx deleted."
      ;;
    haproxy)
      confirm_service_action "Delete HAProxy completely? This can stop port 443 routing." || { echo "Cancelled."; return; }
      systemctl disable --now haproxy 2>/dev/null || true
      apt-get purge -y haproxy 2>/dev/null || apt-get remove -y haproxy 2>/dev/null || true
      rm -rf /etc/haproxy
      systemctl daemon-reload
      echo "HAProxy deleted."
      ;;
    udp)
      confirm_service_action "Delete UDP Custom completely?" || { echo "Cancelled."; return; }
      systemctl disable --now udp-custom 2>/dev/null || true
      rm -f /etc/systemd/system/udp-custom.service /usr/local/bin/sultan-udp-relay
      userdel sultan-udp 2>/dev/null || true
      groupdel sultan-udp 2>/dev/null || true
      systemctl daemon-reload
      echo "UDP Custom deleted."
      ;;
    websocket)
      confirm_service_action "Delete WebSocket completely? This can disconnect SSH over WebSocket." || { echo "Cancelled."; return; }
      systemctl disable --now sultan-ws 2>/dev/null || true
      rm -f /etc/systemd/system/sultan-ws.service /usr/local/bin/sultan-ssh-ws
      userdel sultan-ws 2>/dev/null || true
      groupdel sultan-ws 2>/dev/null || true
      systemctl daemon-reload
      echo "WebSocket deleted."
      ;;
    ssltls)
      D="$(get_domain)"
      validate_domain "$D" || { echo "No valid domain saved."; return; }
      confirm_service_action "Delete SSL/TLS certificate files for $D?" || { echo "Cancelled."; return; }
      certbot delete --cert-name "$D" --non-interactive 2>/dev/null || true
      rm -rf "/etc/sultan/selfsigned/$D"
      echo "SSL/TLS certificate files deleted for $D."
      ;;
    bbr)
      confirm_service_action "Delete BBR configuration?" || { echo "Cancelled."; return; }
      rm -f /etc/sysctl.d/99-sultan-bbr.conf
      sed -i '/net.core.default_qdisc=fq/d;/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf 2>/dev/null || true
      if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw cubic; then
        sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
      fi
      sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1 || true
      sysctl --system >/dev/null 2>&1 || true
      echo "BBR deleted/disabled."
      ;;
    fail2ban)
      confirm_service_action "Delete Fail2Ban completely?" || { echo "Cancelled."; return; }
      systemctl disable --now fail2ban 2>/dev/null || true
      apt-get purge -y fail2ban 2>/dev/null || apt-get remove -y fail2ban 2>/dev/null || true
      rm -rf /etc/fail2ban
      systemctl daemon-reload
      echo "Fail2Ban deleted."
      ;;
    port)
      confirm_service_action "Delete public VPN port rules from UFW? SSH port will not be touched." || { echo "Cancelled."; return; }
      if command -v ufw >/dev/null 2>&1; then
        for P in 80/tcp 443/tcp 8080/tcp 7300/udp; do
          ufw delete allow "$P" >/dev/null 2>&1 || true
          ufw delete deny "$P" >/dev/null 2>&1 || true
        done
        ufw reload >/dev/null 2>&1 || true
        ufw status verbose || true
      fi
      echo "Public VPN port rules deleted from UFW."
      ;;
    xray)
      confirm_service_action "Delete Xray completely? This removes Xray binary, config, and service." || { echo "Cancelled."; return; }
      systemctl disable --now xray 2>/dev/null || true
      rm -f /etc/systemd/system/xray.service /etc/systemd/system/xray@.service
      rm -f /usr/local/bin/xray
      rm -rf /usr/local/etc/xray /usr/local/share/xray /var/log/xray
      systemctl daemon-reload
      echo "Xray deleted."
      ;;
  esac
}

reinstall_all_server_mini(){
  refresh_screen
  echo "========================================"
  echo "          RESTART / REINSTALL SERVER"
  echo "========================================"
  echo "This will run:"
  echo "bash <(curl -fsSL https://raw.githubusercontent.com/sultanmuhamad736-maker/sultan-vip/main/install-mini.sh)"
  echo ""
  confirm_service_action "This will reinstall the server setup." || { echo "Cancelled."; pause; return; }
  bash <(curl -fsSL https://raw.githubusercontent.com/sultanmuhamad736-maker/sultan-vip/main/install-mini.sh)
  pause
}

remove_script(){
  refresh_screen
  read -p "Type YES to remove: " C
  C="$(echo "$C" | tr '[:lower:]' '[:upper:]')"
  [ "$C" = "YES" ] || return

  TMP_USERS="$(mktemp "$BASE/.remove-users.XXXXXX")" || return
  awk -F'|' 'NF{print $1}' /etc/sultan/users.db > "$TMP_USERS" 2>/dev/null || true
  while IFS= read -r U; do
    [ -n "$U" ] || continue
    delete_managed_ssh_user "$U" || echo "Skipped user: $U"
  done < "$TMP_USERS"
  rm -f "$TMP_USERS"

  systemctl disable --now sultan-ws udp-custom sultan-quota.timer sultan-quota.service xray 2>/dev/null || true
  rm -f /etc/systemd/system/sultan-ws.service
  rm -f /etc/systemd/system/udp-custom.service
  rm -f /etc/systemd/system/sultan-quota.service
  rm -f /etc/systemd/system/sultan-quota.timer
  rm -f /etc/systemd/system/xray.service /etc/systemd/system/xray@.service
  rm -rf /etc/systemd/system/xray.service.d
  rm -f /usr/local/bin/xray /usr/local/share/xray/geoip.dat /usr/local/share/xray/geosite.dat
  rm -rf /usr/local/etc/xray /usr/local/share/xray
  rm -f /usr/local/bin/sultan-ssh-ws
  rm -f /usr/local/bin/sultan-udp-relay
  rm -f /usr/local/sbin/sultan-login-limit
  rm -f /usr/local/sbin/sultan-quota-sync
  rm -f /usr/local/sbin/sultan-tunnel-shell
  sed -i '\|/usr/local/sbin/sultan-tunnel-shell|d' /etc/shells 2>/dev/null || true
  rm -f /etc/systemd/system/user-.slice.d/50-sultan-ipaccounting.conf
  sed -i '\|/usr/local/sbin/sultan-login-limit|d' /etc/pam.d/sshd 2>/dev/null || true
  rm -f /etc/ssh/sshd_config.d/98-sultan-legacy-login.conf /etc/ssh/sshd_config.d/99-sultan-users.conf
  rm -f /etc/nginx/conf.d/sultan-ready.conf
  rm -f /etc/letsencrypt/renewal-hooks/deploy/sultan-reload.sh
  rm -f /etc/fail2ban/jail.d/sultan-sshd.conf
  rm -f /etc/sysctl.d/99-sultan-bbr.conf
  sysctl --system >/dev/null 2>&1 || true
  nft delete table inet sultan_quota 2>/dev/null || true
  nft delete table inet sultan_limits 2>/dev/null || true
  ufw --force delete allow 80/tcp >/dev/null 2>&1 || true
  ufw --force delete allow 443/tcp >/dev/null 2>&1 || true
  ufw --force delete allow 7300/udp >/dev/null 2>&1 || true
  if [ -f /etc/haproxy/haproxy.cfg ] && grep -q "SULTAN MANAGED" /etc/haproxy/haproxy.cfg; then
    LATEST_BAK="$(ls -1t /etc/haproxy/haproxy.cfg.sultan.bak.* 2>/dev/null | head -n1 || true)"
    [ -n "$LATEST_BAK" ] && cp -a "$LATEST_BAK" /etc/haproxy/haproxy.cfg
  fi
  rm -rf /etc/sultan
  rm -f /usr/local/bin/menu
  systemctl daemon-reload
  safe_restart_ssh || true
  echo "SULTAN removed"
  exit
}

case "${1:-}" in
  --ready-install)
    SULTAN_NONINTERACTIVE=1
    setup_ready
    exit $?
    ;;
  --health-check)
    SULTAN_NONINTERACTIVE=1
    full_install_self_test "$(get_domain)"
    exit $?
    ;;
esac

main_menu
PANEL

chmod +x "$PANEL"

echo "[5/6] Enabling services..."
systemctl daemon-reload
systemctl enable sultan-quota.timer >/dev/null 2>&1 || true
systemctl restart sultan-quota.timer
systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
systemctl enable nginx haproxy vnstat fail2ban 2>/dev/null || true
if sshd -t; then
  if current_session_via_ws; then
    echo "Current SSH session uses WebSocket; SSH reload skipped."
  else
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  fi
else
  echo "SSH config error. Reload skipped."
fi
systemctl restart vnstat 2>/dev/null || true

CURRENT_SSH_IP="${SSH_CONNECTION%% *}"
case "$CURRENT_SSH_IP" in
  ''|*[!0-9a-fA-F:.]*) CURRENT_SSH_IP="" ;;
esac
mkdir -p /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/sultan-sshd.conf <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
ignoreip = 127.0.0.1/8 ::1 $CURRENT_SSH_IP
EOF
if current_session_via_ws; then
  echo "Current SSH session uses WebSocket; Fail2Ban restart skipped to protect this session."
else
  systemctl restart fail2ban 2>/dev/null || {
  echo "Fail2Ban restart failed; installation will continue without closing SSH."
  }
fi
[ -n "$CURRENT_SSH_IP" ] && fail2ban-client set sshd unbanip "$CURRENT_SSH_IP" >/dev/null 2>&1 || true

modprobe tcp_bbr 2>/dev/null || true
cat >/etc/sysctl.d/99-sultan-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p /etc/sysctl.d/99-sultan-bbr.conf >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true

/usr/local/sbin/sultan-quota-sync || true

echo "[6/6] Ready setup..."
echo "You will be asked for your domain. The installer will continue automatically after setup."
SULTAN_INSTALL_STATUS=0
if ! "$PANEL" --ready-install; then
  echo "Ready setup failed. Fix the error above, then run: menu"
  echo "Xray status:"
  systemctl status xray --no-pager -l 2>/dev/null || true
  journalctl -u xray -n 30 --no-pager 2>/dev/null || true
  SULTAN_INSTALL_STATUS=1
fi

if [ "$SULTAN_INSTALL_STATUS" -eq 0 ]; then
  if current_session_via_ws; then
    echo "Final live WebSocket test skipped now to protect this SSH session."
  elif ! "$PANEL" --health-check; then
    echo "Final service and V2Ray WebSocket verification failed."
    SULTAN_INSTALL_STATUS=1
  fi
fi

if [ "$SULTAN_INSTALL_STATUS" -eq 0 ]; then
  echo ""
  echo "[Before final stage] Checking existing SSH users..."
  handle_existing_users_before_final || {
    echo "Existing-user delete/import step failed."
    SULTAN_INSTALL_STATUS=1
  }
fi

if [ "$SULTAN_INSTALL_STATUS" -eq 0 ]; then
  echo ""
  echo "[7/7] Installing final mini package..."
  if ! SULTAN_MINI_CHAINED=1 bash <(curl -fsSL https://raw.githubusercontent.com/sultanmuhamad736-maker/sultan-vip/main/install-mini.sh); then
    echo "Final mini installation failed."
    SULTAN_INSTALL_STATUS=1
  fi
fi

echo ""
echo "==========================================="
if [ "$SULTAN_INSTALL_STATUS" -eq 0 ]; then
  echo "Installation verified. Type: menu"
  echo "Mandatory HTTP 101 / 502 prevention: PASSED"
else
  echo "Installation verification FAILED."
  echo "Mandatory HTTP 101 / 502 prevention did not pass."
  echo "Fix the reported error, then run: menu -> 10 -> 1"
fi
echo "Max Login 0 = Unlimited"
echo "GB Limit  0 = Unlimited"
echo "Quota check: every 3 seconds"
echo "==========================================="

return "$SULTAN_INSTALL_STATUS" 2>/dev/null || true
