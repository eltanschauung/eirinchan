#!/bin/sh
set -eu

database_dir="${GEOIPUPDATE_DB_DIR:-/usr/share/GeoIP}"
database_path="$database_dir/GeoLite2-Country.mmdb"
stamp_path="$database_dir/.eirinchan-geoip-month"

run_update() {
  GEOIPUPDATE_FREQUENCY=0 /usr/bin/entry.sh
  current_month="$(date '+%Y-%m')"
  temporary_stamp="$stamp_path.$$"
  printf '%s\n' "$current_month" >"$temporary_stamp"
  mv -f -- "$temporary_stamp" "$stamp_path"
}

if [ "${1:-}" = "--once" ]; then
  run_update
  exit 0
fi

trap 'exit 0' INT TERM

while :; do
  current_month="$(date '+%Y-%m')"
  current_day="$(date '+%d')"
  updated_month="$(cat "$stamp_path" 2>/dev/null || true)"

  if [ ! -s "$database_path" ] || { [ "$current_day" = "01" ] && [ "$updated_month" != "$current_month" ]; }; then
    if ! run_update; then
      echo "GeoIP database update failed; retrying in one hour." >&2
    fi
  fi

  sleep 3600 &
  wait $! || exit 0
done
