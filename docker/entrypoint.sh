#!/usr/bin/env sh
set -eu

state_root="${EIRINCHAN_STATE_ROOT:-/var/lib/eirinchan}"
secret_root="${EIRINCHAN_SECRET_ROOT:-/run/secrets}"

read_secret() {
  secret_file="$1"

  if [ ! -r "$secret_file" ]; then
    echo "Required secret is unavailable: $secret_file" >&2
    exit 78
  fi

  value="$(cat "$secret_file")"

  if [ -z "$value" ]; then
    echo "Required secret is empty: $secret_file" >&2
    exit 78
  fi

  printf '%s' "$value"
}

if [ "$(id -u)" -eq 0 ]; then
  install -d -m 0700 -o eirinchan -g eirinchan "$state_root"
  install -d -m 0700 -o eirinchan -g eirinchan \
    "$state_root/tmp" \
    "$state_root/tmp/build" \
    "$state_root/var" \
    "$state_root/var/invalid_uploads" \
    "$state_root/var/log"
fi

SECRET_KEY_BASE="$(read_secret "$secret_root/secret_key_base")"
export SECRET_KEY_BASE
postgres_password="$(read_secret "$secret_root/postgres_password")"

database_host="${POSTGRES_HOST:-database}"
database_port="${POSTGRES_PORT:-5432}"
database_name="${POSTGRES_DB:-eirinchan}"
database_user="${POSTGRES_USER:-eirinchan}"

export DATABASE_URL="ecto://${database_user}:${postgres_password}@${database_host}:${database_port}/${database_name}"
unset postgres_password

if [ "$(id -u)" -eq 0 ]; then
  exec gosu eirinchan "$@"
fi

exec "$@"
