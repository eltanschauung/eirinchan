#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${1:-/home/telemazer/eirinchan-v1}"
RELEASE_ROOT=/opt/eirinchan/releases
CURRENT_LINK=/opt/eirinchan/current
SERVICE=bantculture-phoenix.service
DROP_IN=/etc/systemd/system/bantculture-phoenix.service.d/hardening.conf

REPOSITORY="$(realpath -- "$REPOSITORY")"
COMMIT="$(git -C "$REPOSITORY" rev-parse HEAD)"

if [[ ! "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Refusing invalid release identifier: $COMMIT" >&2
  exit 1
fi

BUILD_ROOT="$(mktemp -d /home/telemazer/eirinchan-v1/tmp/release-build.XXXXXX)"
SOURCE_ROOT="$BUILD_ROOT/source"
OUTPUT_ROOT="$BUILD_ROOT/output"
TARGET="$RELEASE_ROOT/$COMMIT"
TEMP_TARGET="$RELEASE_ROOT/.${COMMIT}.new"
PREVIOUS_TARGET=""
PREVIOUS_DROP_IN="$BUILD_ROOT/previous-hardening.conf"
HAD_DROP_IN=0

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

# This legacy static alias points at the mutable upload tree. Mix release
# dereferences application priv symlinks, so omit it while assembling and add
# it back to the finished release as a symlink.
if [[ -L "$SOURCE_ROOT/priv/static/bant_files" ]]; then
  rm -- "$SOURCE_ROOT/priv/static/bant_files"
fi

export PATH="/home/telemazer/.local/elixir-1.20.2-otp-27/bin:/home/telemazer/.local/otp-27.3.4.12/bin:${PATH}"
export MIX_HOME=/home/telemazer/.mix-1.20
export HEX_HOME=/home/telemazer/.hex-1.20
export MIX_ENV=prod

cd "$SOURCE_ROOT"
mix deps.get --only prod
mix compile
mix release --path "$OUTPUT_ROOT" --overwrite

APP_STATIC="$(find "$OUTPUT_ROOT/lib" -type d -path '*/priv/static' -print -quit)"
if [[ -z "$APP_STATIC" ]]; then
  echo "Release static directory was not generated." >&2
  exit 1
fi
rsync -a --exclude=/bant_files -- "$REPOSITORY/priv/static/" "$APP_STATIC/"
ln -s -- /home/telemazer/eirinchan-v1/tmp/build/bant/src "$APP_STATIC/bant_files"

sudo install -d -m 0755 -o root -g root /opt/eirinchan "$RELEASE_ROOT"
if [[ ! -e "$TARGET" ]]; then
  sudo install -d -m 0700 -o root -g root "$TEMP_TARGET"
  sudo cp -a -- "$OUTPUT_ROOT/." "$TEMP_TARGET/"
  sudo chown -R root:root "$TEMP_TARGET"
  sudo find "$TEMP_TARGET" -type d -exec chmod 0555 {} +
  sudo find "$TEMP_TARGET" -type f -perm /111 -exec chmod 0555 {} +
  sudo find "$TEMP_TARGET" -type f ! -perm /111 -exec chmod 0444 {} +
  sudo mv -- "$TEMP_TARGET" "$TARGET"
fi

sudo -u telemazer "$TARGET/bin/migrate"

sudo install -m 0644 -o root -g root \
  "$REPOSITORY/ops/systemd/bantculture-phoenix.service.d/hardening.conf" \
  "$DROP_IN"
sudo install -m 0644 -o root -g root \
  "$REPOSITORY/ops/logrotate/bantculture-phoenix" \
  /etc/logrotate.d/bantculture-phoenix

if ! command -v goaccess >/dev/null 2>&1; then
  echo "GoAccess is required to validate the production access log." >&2
  exit 1
fi

# Debian ships every log format disabled. Select the standard Combined preset
# so `goaccess ~/eirinchan-v1/access.log` works without additional arguments.
sudo sed -i 's/^#log-format COMBINED$/log-format COMBINED/' /etc/goaccess/goaccess.conf
sudo grep -qxF 'log-format COMBINED' /etc/goaccess/goaccess.conf

sudo install -m 0644 -o root -g root \
  "$REPOSITORY/ops/systemd/eirinchan-log-retention.service" \
  /etc/systemd/system/eirinchan-log-retention.service
sudo install -m 0644 -o root -g root \
  "$REPOSITORY/ops/systemd/eirinchan-log-retention.timer" \
  /etc/systemd/system/eirinchan-log-retention.timer
sudo rm -f -- /etc/tmpfiles.d/eirinchan-logs.conf
sudo install -d -m 0700 -o root -g root /home/telemazer/logs
sudo touch /home/telemazer/logs/bantculture-phoenix.log
sudo chown root:root /home/telemazer/logs/bantculture-phoenix.log
sudo chmod 0600 /home/telemazer/logs/bantculture-phoenix.log
sudo touch "$REPOSITORY/access.log"
sudo chown telemazer:telemazer "$REPOSITORY/access.log"
sudo chmod 0600 "$REPOSITORY/access.log"

sudo rm -f -- /opt/eirinchan/current.new /opt/eirinchan/current.rollback
sudo ln -s -- "$TARGET" /opt/eirinchan/current.new
sudo mv -Tf -- /opt/eirinchan/current.new "$CURRENT_LINK"
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE"

healthy=0
for _attempt in $(seq 1 45); do
  if curl -fsS --max-time 5 https://bantculture.com/ >/dev/null; then
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
    sudo ln -s -- "$PREVIOUS_TARGET" /opt/eirinchan/current.rollback
    sudo mv -Tf -- /opt/eirinchan/current.rollback "$CURRENT_LINK"
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

printf 'Deployed immutable release %s\n' "$COMMIT"
