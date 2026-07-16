#!/usr/bin/env bash
set -euo pipefail

repository="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
temporary="$(mktemp -d /tmp/eirinchan-cli-test.XXXXXX)"
trap 'rm -rf -- "$temporary"' EXIT

sandbox="$temporary/repository"
fake_bin="$temporary/bin"
docker_log="$temporary/docker.log"
admin_marker="$temporary/admin-created"

mkdir -p "$sandbox" "$fake_bin"
cp "$repository/eirinchan" "$repository/compose.yaml" "$sandbox/"

cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >>"$FAKE_DOCKER_LOG"
printf '\n' >>"$FAKE_DOCKER_LOG"

if [ "${1:-}" = "info" ]; then
  exit 0
fi

if [ "${1:-}" = "inspect" ]; then
  echo healthy
  exit 0
fi

[ "${1:-}" = "compose" ] || exit 1
shift

if [ "${1:-}" = "version" ]; then
  echo "Docker Compose version v5.0.0-test"
  exit 0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-directory | --env-file | --file | --profile)
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

command="${1:-}"
shift || true

case "$command" in
  config | pull | build | up | down | logs)
    exit 0
    ;;
  ps)
    if [[ " $* " == *" -q "* ]]; then
      echo fake-container-id
    else
      echo "NAME STATUS"
    fi
    ;;
  run)
    if [[ " $* " == *" /app/bin/admin-exists "* ]]; then
      exit 1
    fi

    if [[ " $* " == *" /app/bin/create-admin "* ]]; then
      password="$(cat)"
      [ "$password" = "correct horse battery staple" ]
      : >"$FAKE_ADMIN_MARKER"
    fi
    ;;
  *)
    echo "unexpected fake Docker command: $command $*" >&2
    exit 1
    ;;
esac
EOF

chmod 0755 "$fake_bin/docker" "$sandbox/eirinchan"

export FAKE_DOCKER_LOG="$docker_log"
export FAKE_ADMIN_MARKER="$admin_marker"

PATH="$fake_bin:$PATH" "$sandbox/eirinchan" install \
  >"$temporary/install.out" <<'EOF'
chan.example.com
n
owner
correct horse battery staple
correct horse battery staple
EOF

test -f "$admin_marker"
grep -q 'Eirinchan is installed.' "$temporary/install.out"
grep -q 'https://chan.example.com/manage/login' "$temporary/install.out"

test "$(stat -c '%a' "$sandbox/.eirinchan")" = "700"
test "$(stat -c '%a' "$sandbox/.eirinchan/secrets")" = "700"
test "$(stat -c '%a' "$sandbox/.eirinchan/install.env")" = "600"
test "$(stat -c '%a' "$sandbox/.eirinchan/secrets/postgres_password")" = "600"
test "$(stat -c '%a' "$sandbox/.eirinchan/secrets/secret_key_base")" = "600"

grep -q '^EIRINCHAN_HOST=chan.example.com$' "$sandbox/.eirinchan/install.env"
grep -q '^EIRINCHAN_GEOIP_ENABLED=0$' "$sandbox/.eirinchan/install.env"
test "$(tr -d '\n' <"$sandbox/.eirinchan/secrets/postgres_password" | wc -c)" = "64"
test "$(tr -d '\n' <"$sandbox/.eirinchan/secrets/secret_key_base" | wc -c)" = "128"

if grep -q 'correct horse battery staple' "$docker_log"; then
  echo "administrator password leaked into Docker arguments" >&2
  exit 1
fi

PATH="$fake_bin:$PATH" "$sandbox/eirinchan" doctor >"$temporary/doctor.out"
grep -q 'Installation files and Compose configuration are valid.' "$temporary/doctor.out"

geoip_sandbox="$temporary/geoip-repository"
mkdir -p "$geoip_sandbox"
cp "$repository/eirinchan" "$repository/compose.yaml" "$geoip_sandbox/"
chmod 0755 "$geoip_sandbox/eirinchan"

export FAKE_DOCKER_LOG="$temporary/geoip-docker.log"
export FAKE_ADMIN_MARKER="$temporary/geoip-admin-created"

PATH="$fake_bin:$PATH" "$geoip_sandbox/eirinchan" install \
  >"$temporary/geoip-install.out" <<'EOF'
geo.example.com
y
123456
test-license-key-1234567890
owner
correct horse battery staple
correct horse battery staple
EOF

test -f "$FAKE_ADMIN_MARKER"
grep -q '^EIRINCHAN_GEOIP_ENABLED=1$' "$geoip_sandbox/.eirinchan/install.env"
test "$(stat -c '%a' "$geoip_sandbox/.eirinchan/secrets/maxmind_account_id")" = "600"
test "$(stat -c '%a' "$geoip_sandbox/.eirinchan/secrets/maxmind_license_key")" = "600"
grep -q '^123456$' "$geoip_sandbox/.eirinchan/secrets/maxmind_account_id"
grep -q '^test-license-key-1234567890$' "$geoip_sandbox/.eirinchan/secrets/maxmind_license_key"
grep -q -- '--profile geoip' "$FAKE_DOCKER_LOG"

if grep -q 'test-license-key-1234567890' "$FAKE_DOCKER_LOG"; then
  echo "MaxMind license key leaked into Docker arguments" >&2
  exit 1
fi

echo "CLI installer test passed"
