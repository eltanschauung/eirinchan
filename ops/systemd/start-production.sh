#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/telemazer/.local/elixir-1.20.2-otp-27/bin:/home/telemazer/.local/otp-27.3.4.12/bin:${PATH}"
export MIX_HOME="/home/telemazer/.mix-1.20"
export HEX_HOME="/home/telemazer/.hex-1.20"

set -a
source /home/telemazer/.config/eirinchan-shared.env
set +a

cd /home/telemazer/eirinchan-v1
export MIX_ENV=prod
export PHX_SERVER=true
export PHX_HOST=bantculture.com
export PORT=4001
export SECRET_KEY_BASE="$(tail -n 1 /home/telemazer/.config/eirinchan4001/secret_key_base)"

exec mix phx.server
