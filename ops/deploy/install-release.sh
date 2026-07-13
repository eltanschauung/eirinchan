#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${1:-/home/telemazer/eirinchan-v1}"
RELEASE_ROOT=/opt/eirinchan/releases
CURRENT_LINK=/opt/eirinchan/current
SERVICE=bantculture-phoenix.service

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
PREVIOUS_TARGET="$(readlink -f -- "$CURRENT_LINK" 2>/dev/null || true)"

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
  /etc/systemd/system/bantculture-phoenix.service.d/hardening.conf
sudo install -m 0644 -o root -g root \
  "$REPOSITORY/ops/logrotate/bantculture-phoenix" \
  /etc/logrotate.d/bantculture-phoenix
sudo rm -f -- /etc/tmpfiles.d/eirinchan-logs.conf
sudo install -d -m 0700 -o root -g root /home/telemazer/logs
sudo touch /home/telemazer/logs/bantculture-phoenix.log
sudo chown root:root /home/telemazer/logs/bantculture-phoenix.log
sudo chmod 0600 /home/telemazer/logs/bantculture-phoenix.log

sudo ln -s -- "$TARGET" /opt/eirinchan/current.new
sudo mv -Tf -- /opt/eirinchan/current.new "$CURRENT_LINK"
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE"

healthy=0
for _attempt in $(seq 1 45); do
  if curl -fsS --max-time 5 https://bantculture.com/ >/dev/null; then
    healthy=1
    break
  fi
  sleep 1
done

if [[ "$healthy" -ne 1 ]]; then
  if [[ -n "$PREVIOUS_TARGET" && -d "$PREVIOUS_TARGET" ]]; then
    sudo ln -s -- "$PREVIOUS_TARGET" /opt/eirinchan/current.rollback
    sudo mv -Tf -- /opt/eirinchan/current.rollback "$CURRENT_LINK"
    sudo systemctl restart "$SERVICE"
  fi
  echo "Release health check failed; restored the previous release." >&2
  exit 1
fi

printf 'Deployed immutable release %s\n' "$COMMIT"
