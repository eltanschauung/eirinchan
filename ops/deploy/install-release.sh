#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPOSITORY="${1:-$(realpath -- "$SCRIPT_DIR/../..")}"
DEPLOY_USER="${EIRINCHAN_DEPLOY_USER:-telemazer}"
DEPLOY_GROUP="${EIRINCHAN_DEPLOY_GROUP:-$DEPLOY_USER}"
DEPLOY_HOME="${EIRINCHAN_DEPLOY_HOME:-/home/$DEPLOY_USER}"
RELEASE_ROOT="${EIRINCHAN_RELEASE_ROOT:-/opt/eirinchan/releases}"
CURRENT_LINK="${EIRINCHAN_CURRENT_LINK:-/opt/eirinchan/current}"
SERVICE="${EIRINCHAN_SYSTEMD_SERVICE:-bantculture-phoenix.service}"
DROP_IN="${EIRINCHAN_SYSTEMD_DROP_IN:-/etc/systemd/system/${SERVICE}.d/hardening.conf}"
LOG_DIR="${EIRINCHAN_PHOENIX_LOG_DIR:-$DEPLOY_HOME/logs}"
PHOENIX_LOG_NAME="${EIRINCHAN_PHOENIX_LOG_NAME:-bantculture-phoenix.log}"
LOGROTATE_NAME="${EIRINCHAN_LOGROTATE_NAME:-bantculture-phoenix}"
PHX_HOST="${EIRINCHAN_DEPLOY_HOST:-bantculture.com}"
PHX_PORT="${EIRINCHAN_DEPLOY_PORT:-4001}"
SHARED_ENV="${EIRINCHAN_SHARED_ENV:-$DEPLOY_HOME/.config/eirinchan-shared.env}"
SECRET_KEY_FILE="${EIRINCHAN_SECRET_KEY_FILE:-$DEPLOY_HOME/.config/eirinchan4001/secret_key_base}"
GEOIP_CONFIG="${EIRINCHAN_GEOIP_CONFIG:-$DEPLOY_HOME/.config/maxmind/GeoIP.conf}"
TOOLCHAIN_ID="${EIRINCHAN_TOOLCHAIN_ID:-elixir-1.20.2-otp-27}"
ELIXIR_BIN="${EIRINCHAN_ELIXIR_BIN:-$DEPLOY_HOME/.local/elixir-1.20.2-otp-27/bin}"
OTP_BIN="${EIRINCHAN_OTP_BIN:-$DEPLOY_HOME/.local/otp-27.3.4.12/bin}"
MIX_HOME="${EIRINCHAN_MIX_HOME:-$DEPLOY_HOME/.mix-1.20}"
HEX_HOME="${EIRINCHAN_HEX_HOME:-$DEPLOY_HOME/.hex-1.20}"

REPOSITORY="$(realpath -- "$REPOSITORY")"

valid_path() { [[ "$1" =~ ^/[A-Za-z0-9._/-]+$ ]]; }
valid_name() { [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; }

valid_path "$REPOSITORY" || { echo "Refusing repository path with unsupported characters." >&2; exit 1; }
valid_name "$DEPLOY_USER" || { echo "Invalid EIRINCHAN_DEPLOY_USER." >&2; exit 1; }
valid_name "$DEPLOY_GROUP" || { echo "Invalid EIRINCHAN_DEPLOY_GROUP." >&2; exit 1; }
[[ "$SERVICE" =~ ^[A-Za-z0-9_.@-]+\.service$ ]] || { echo "Invalid EIRINCHAN_SYSTEMD_SERVICE." >&2; exit 1; }
[[ "$LOGROTATE_NAME" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid EIRINCHAN_LOGROTATE_NAME." >&2; exit 1; }
[[ "$PHOENIX_LOG_NAME" =~ ^[A-Za-z0-9_.-]+\.log$ ]] || { echo "Invalid EIRINCHAN_PHOENIX_LOG_NAME." >&2; exit 1; }
[[ "$PHX_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Invalid EIRINCHAN_DEPLOY_HOST." >&2; exit 1; }
if [[ ! "$PHX_PORT" =~ ^[0-9]+$ ]] || ((PHX_PORT < 1 || PHX_PORT > 65535)); then
  echo "Invalid EIRINCHAN_DEPLOY_PORT." >&2
  exit 1
fi
[[ "$TOOLCHAIN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid EIRINCHAN_TOOLCHAIN_ID." >&2; exit 1; }

for configured_path in "$DEPLOY_HOME" "$RELEASE_ROOT" "$CURRENT_LINK" "$DROP_IN" "$LOG_DIR" \
  "$SHARED_ENV" "$SECRET_KEY_FILE" "$GEOIP_CONFIG" "$ELIXIR_BIN" "$OTP_BIN" "$MIX_HOME" "$HEX_HOME"; do
  valid_path "$configured_path" || { echo "Refusing configured path with unsupported characters: $configured_path" >&2; exit 1; }
done

id -u "$DEPLOY_USER" >/dev/null 2>&1 || { echo "Deployment user does not exist: $DEPLOY_USER" >&2; exit 1; }
getent group "$DEPLOY_GROUP" >/dev/null 2>&1 || { echo "Deployment group does not exist: $DEPLOY_GROUP" >&2; exit 1; }
[[ -r "$SHARED_ENV" ]] || { echo "Shared environment file is not readable: $SHARED_ENV" >&2; exit 1; }
[[ -r "$SECRET_KEY_FILE" ]] || { echo "Secret key file is not readable: $SECRET_KEY_FILE" >&2; exit 1; }

COMMIT="$(git -C "$REPOSITORY" rev-parse HEAD)"
CACHE_ROOT="${EIRINCHAN_DEPLOY_CACHE_ROOT:-${HOME}/.cache/eirinchan/deploy/${TOOLCHAIN_ID}}"
RUN_ROOT="$CACHE_ROOT/runs"

if [[ ! "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Refusing invalid release identifier: $COMMIT" >&2
  exit 1
fi

install -d -m 0700 "$CACHE_ROOT" "$RUN_ROOT" "$CACHE_ROOT/deps" "$CACHE_ROOT/build"
[[ -O "$CACHE_ROOT" ]] || { echo "Deploy cache is not owned by the current user." >&2; exit 1; }
chmod 0700 "$CACHE_ROOT" "$RUN_ROOT" "$CACHE_ROOT/deps" "$CACHE_ROOT/build"

exec 9>"$CACHE_ROOT/deploy.lock"
flock 9

BUILD_ROOT="$(mktemp -d "$RUN_ROOT/release.XXXXXX")"
SOURCE_ROOT="$BUILD_ROOT/source"
OUTPUT_ROOT="$BUILD_ROOT/output"
HARDENING_RENDERED="$BUILD_ROOT/hardening.conf"
LOG_RETENTION_RENDERED="$BUILD_ROOT/eirinchan-log-retention.service"
GEOIP_UPDATE_RENDERED="$BUILD_ROOT/eirinchan-geoip-update.service"
TARGET="$RELEASE_ROOT/$COMMIT"
TEMP_TARGET="$RELEASE_ROOT/.${COMMIT}.new"
PREVIOUS_TARGET=""
PREVIOUS_DROP_IN="$BUILD_ROOT/previous-hardening.conf"
HAD_DROP_IN=0

render_tokens() {
  local file="$1"

  sed -i \
    -e "s|@EIRINCHAN_STATE_ROOT@|$REPOSITORY|g" \
    -e "s|@EIRINCHAN_DEPLOY_USER@|$DEPLOY_USER|g" \
    -e "s|@EIRINCHAN_DEPLOY_GROUP@|$DEPLOY_GROUP|g" \
    -e "s|@EIRINCHAN_SERVICE@|$SERVICE|g" \
    -e "s|@EIRINCHAN_CURRENT_LINK@|$CURRENT_LINK|g" \
    -e "s|@EIRINCHAN_LOG_DIR@|$LOG_DIR|g" \
    -e "s|@EIRINCHAN_PHOENIX_LOG_NAME@|$PHOENIX_LOG_NAME|g" \
    -e "s|@EIRINCHAN_SHARED_ENV@|$SHARED_ENV|g" \
    -e "s|@EIRINCHAN_SECRET_KEY_FILE@|$SECRET_KEY_FILE|g" \
    -e "s|@EIRINCHAN_HOST@|$PHX_HOST|g" \
    -e "s|@EIRINCHAN_PORT@|$PHX_PORT|g" \
    -e "s|@EIRINCHAN_GEOIP_CONFIG@|$GEOIP_CONFIG|g" \
    "$file"

  if grep -qE '@EIRINCHAN_[A-Z_]+@' "$file"; then
    echo "Failed to render deployment template: $file" >&2
    exit 1
  fi
}

if [[ -L "$CURRENT_LINK" ]]; then
  candidate="$(readlink -f -- "$CURRENT_LINK" 2>/dev/null || true)"

  if [[ "$candidate" == "$RELEASE_ROOT/"* && -d "$candidate" ]]; then
    PREVIOUS_TARGET="$candidate"
  fi
fi

if sudo test -f "$DROP_IN"; then
  sudo cp -- "$DROP_IN" "$PREVIOUS_DROP_IN"
  sudo chown "$(id -u):$(id -g)" "$PREVIOUS_DROP_IN"
  HAD_DROP_IN=1
fi

cleanup() {
  git -C "$REPOSITORY" worktree remove --force "$SOURCE_ROOT" >/dev/null 2>&1 || true
  rm -rf -- "$BUILD_ROOT"
}
trap cleanup EXIT

git -C "$REPOSITORY" worktree add --detach "$SOURCE_ROOT" "$COMMIT"

export PATH="$ELIXIR_BIN:$OTP_BIN:${PATH}"
export MIX_HOME
export HEX_HOME
export MIX_ENV=prod
export MIX_DEPS_PATH="$CACHE_ROOT/deps"
export MIX_BUILD_PATH="$CACHE_ROOT/build"

cd "$SOURCE_ROOT"
mix deps.get --only prod --check-locked
mix compile
mix release --path "$OUTPUT_ROOT" --overwrite

for script in start-production migrate log-retention; do
  render_tokens "$OUTPUT_ROOT/bin/$script"
done

LOGROTATE_RENDERED="$BUILD_ROOT/logrotate.conf"
cp -- "$SOURCE_ROOT/ops/systemd/bantculture-phoenix.service.d/hardening.conf" "$HARDENING_RENDERED"
cp -- "$SOURCE_ROOT/ops/systemd/eirinchan-log-retention.service" "$LOG_RETENTION_RENDERED"
cp -- "$SOURCE_ROOT/ops/systemd/eirinchan-geoip-update.service" "$GEOIP_UPDATE_RENDERED"
cp -- "$SOURCE_ROOT/ops/logrotate/bantculture-phoenix" "$LOGROTATE_RENDERED"
render_tokens "$HARDENING_RENDERED"
render_tokens "$LOG_RETENTION_RENDERED"
render_tokens "$GEOIP_UPDATE_RENDERED"
render_tokens "$LOGROTATE_RENDERED"

APP_STATIC="$(find "$OUTPUT_ROOT/lib" -type d -path '*/priv/static' -print -quit)"
if [[ -z "$APP_STATIC" ]]; then
  echo "Release static directory was not generated." >&2
  exit 1
fi
rsync -a -- "$SOURCE_ROOT/priv/static/" "$APP_STATIC/"

sudo install -d -m 0755 -o root -g root "$(dirname -- "$RELEASE_ROOT")" "$RELEASE_ROOT" "$(dirname -- "$CURRENT_LINK")"
if [[ ! -e "$TARGET" ]]; then
  sudo install -d -m 0700 -o root -g root "$TEMP_TARGET"
  sudo cp -a -- "$OUTPUT_ROOT/." "$TEMP_TARGET/"
  sudo chown -R root:root "$TEMP_TARGET"
  sudo find "$TEMP_TARGET" -type d -exec chmod 0555 {} +
  sudo find "$TEMP_TARGET" -type f -perm /111 -exec chmod 0555 {} +
  sudo find "$TEMP_TARGET" -type f ! -perm /111 -exec chmod 0444 {} +
  sudo mv -- "$TEMP_TARGET" "$TARGET"
fi

sudo -u "$DEPLOY_USER" "$TARGET/bin/migrate"

sudo install -d -m 0755 -o root -g root "$(dirname -- "$DROP_IN")"
sudo install -m 0644 -o root -g root \
  "$HARDENING_RENDERED" \
  "$DROP_IN"
sudo install -m 0644 -o root -g root \
  "$LOGROTATE_RENDERED" \
  "/etc/logrotate.d/$LOGROTATE_NAME"

if ! command -v goaccess >/dev/null 2>&1; then
  echo "GoAccess is required to validate the production access log." >&2
  exit 1
fi

# Debian ships every log format disabled. Select the standard Combined preset
# so `goaccess "$REPOSITORY/access.log"` works without additional arguments.
sudo sed -i 's/^#log-format COMBINED$/log-format COMBINED/' /etc/goaccess/goaccess.conf
sudo grep -qxF 'log-format COMBINED' /etc/goaccess/goaccess.conf

sudo install -m 0644 -o root -g root \
  "$LOG_RETENTION_RENDERED" \
  /etc/systemd/system/eirinchan-log-retention.service
sudo install -m 0644 -o root -g root \
  "$SOURCE_ROOT/ops/systemd/eirinchan-log-retention.timer" \
  /etc/systemd/system/eirinchan-log-retention.timer
sudo install -m 0644 -o root -g root \
  "$GEOIP_UPDATE_RENDERED" \
  /etc/systemd/system/eirinchan-geoip-update.service
sudo install -m 0644 -o root -g root \
  "$SOURCE_ROOT/ops/systemd/eirinchan-geoip-update.timer" \
  /etc/systemd/system/eirinchan-geoip-update.timer
sudo rm -f -- /etc/tmpfiles.d/eirinchan-logs.conf
sudo install -d -m 0700 -o root -g root "$LOG_DIR"
sudo touch "$LOG_DIR/$PHOENIX_LOG_NAME"
sudo chown root:root "$LOG_DIR/$PHOENIX_LOG_NAME"
sudo chmod 0600 "$LOG_DIR/$PHOENIX_LOG_NAME"
ACCESS_LOG_TARGET="$REPOSITORY/var/log/access.log"
ACCESS_LOG_LINK="$REPOSITORY/access.log"
sudo install -d -m 0700 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" "$REPOSITORY/var/log"

if sudo test -f "$ACCESS_LOG_LINK" && ! sudo test -L "$ACCESS_LOG_LINK"; then
  sudo mv -fT -- "$ACCESS_LOG_LINK" "$ACCESS_LOG_TARGET"
elif sudo test -e "$ACCESS_LOG_LINK" || sudo test -L "$ACCESS_LOG_LINK"; then
  sudo rm -f -- "$ACCESS_LOG_LINK"
fi

sudo touch "$ACCESS_LOG_TARGET"
sudo chown "$DEPLOY_USER:$DEPLOY_GROUP" "$ACCESS_LOG_TARGET"
sudo chmod 0600 "$ACCESS_LOG_TARGET"
sudo ln -s -- "var/log/access.log" "$ACCESS_LOG_LINK"

sudo rm -f -- "${CURRENT_LINK}.new" "${CURRENT_LINK}.rollback"
sudo ln -s -- "$TARGET" "${CURRENT_LINK}.new"
sudo mv -Tf -- "${CURRENT_LINK}.new" "$CURRENT_LINK"
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE"

healthy=0
for _attempt in $(seq 1 45); do
  # Probe Bandit directly. The public route may legitimately return 403 when
  # IP-access protection or an upstream edge policy blocks the VPS itself.
  if curl -fsS --max-time 5 -H "Host: $PHX_HOST" "http://127.0.0.1:$PHX_PORT/" >/dev/null; then
    tail -n 1 "$REPOSITORY/access.log" >"$BUILD_ROOT/goaccess-smoke.log"

    if goaccess "$BUILD_ROOT/goaccess-smoke.log" \
      --output="$BUILD_ROOT/goaccess-smoke.html" >/dev/null 2>&1 &&
      test -s "$BUILD_ROOT/goaccess-smoke.html"; then
      healthy=1
      break
    fi
  fi
  sleep 1
done

if [[ "$healthy" -ne 1 ]]; then
  if [[ -n "$PREVIOUS_TARGET" && -d "$PREVIOUS_TARGET" ]]; then
    sudo ln -s -- "$PREVIOUS_TARGET" "${CURRENT_LINK}.rollback"
    sudo mv -Tf -- "${CURRENT_LINK}.rollback" "$CURRENT_LINK"
  elif [[ "$HAD_DROP_IN" -eq 1 ]]; then
    sudo install -m 0644 -o root -g root "$PREVIOUS_DROP_IN" "$DROP_IN"
  else
    sudo rm -f -- "$DROP_IN"
  fi

  sudo systemctl daemon-reload
  sudo systemctl restart "$SERVICE"
  echo "Release health check failed; restored the previous release." >&2
  exit 1
fi

sudo systemctl enable --now eirinchan-log-retention.timer

if command -v geoipupdate >/dev/null 2>&1 && sudo test -r "$GEOIP_CONFIG"; then
  sudo install -d -m 0700 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" "$REPOSITORY/var/geoip"
  sudo systemctl enable --now eirinchan-geoip-update.timer
fi

printf 'Deployed immutable release %s\n' "$COMMIT"
