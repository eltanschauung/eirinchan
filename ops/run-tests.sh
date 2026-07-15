#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY="$(realpath -- "$SCRIPT_DIR/..")"
TOOLCHAIN_ID=elixir-1.20.2-otp-27
CACHE_ROOT="${EIRINCHAN_TEST_CACHE_ROOT:-${HOME}/.cache/eirinchan/test/${TOOLCHAIN_ID}}"

export PATH="/home/telemazer/.local/elixir-1.20.2-otp-27/bin:/home/telemazer/.local/otp-27.3.4.12/bin:${PATH}"
export MIX_HOME=/home/telemazer/.mix-1.20
export HEX_HOME=/home/telemazer/.hex-1.20

AUTH_TEST_DATABASE_URL="$(
  # Keep the production DATABASE_URL in the shared file out of the test process.
  # shellcheck disable=SC1091
  source /home/telemazer/.config/eirinchan-shared.env
  printf '%s' "${AUTH_TEST_DATABASE_URL:-}"
)"

if [[ -z "${AUTH_TEST_DATABASE_URL:-}" ]]; then
  echo "AUTH_TEST_DATABASE_URL is missing; refusing to run tests." >&2
  exit 1
fi

export TEST_DATABASE_URL="$AUTH_TEST_DATABASE_URL"
export MIX_ENV=test
export MIX_DEPS_PATH="$CACHE_ROOT/deps"
export MIX_BUILD_PATH="$CACHE_ROOT/build"
unset DATABASE_URL PHX_SERVER PORT

install -d -m 0700 "$CACHE_ROOT" "$MIX_DEPS_PATH" "$MIX_BUILD_PATH"
[[ -O "$CACHE_ROOT" ]] || { echo "Test cache is not owned by the current user." >&2; exit 1; }
chmod 0700 "$CACHE_ROOT" "$MIX_DEPS_PATH" "$MIX_BUILD_PATH"

exec 9>"$CACHE_ROOT/test.lock"
flock 9

cd "$REPOSITORY"
mix deps.get --only test --check-locked
exec mix test "$@"
