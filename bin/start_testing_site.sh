#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_NAME="${SESSION_NAME:-eirinchan4001}"
SECRETS_DIR="${HOME}/.config/eirinchan4001"
SECRET_FILE="${SECRETS_DIR}/secret_key_base"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

if [[ ! -s "$SECRET_FILE" ]]; then
  (
    cd "$APP_DIR"
    MIX_ENV=prod mix phx.gen.secret > "$SECRET_FILE"
  )
  chmod 600 "$SECRET_FILE"
fi

if screen -list | grep -q "\\.${SESSION_NAME}\\b"; then
  screen -S "$SESSION_NAME" -X quit || true
fi

screen -dmS "$SESSION_NAME" bash -lc "
cd '$APP_DIR' || exit 1
export MIX_ENV=prod
export PHX_SERVER=true
export PHX_HOST=\"\${PHX_HOST:-testing.bantculture.com}\"
export PORT=\"\${PORT:-4001}\"
export DATABASE_URL=\"\${DATABASE_URL:-ecto://localhost/eirinchan_dev}\"
export SECRET_KEY_BASE=\"\$(< '$SECRET_FILE')\"
mix phx.server
"
