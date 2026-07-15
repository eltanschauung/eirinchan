#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY="$(realpath -- "$SCRIPT_DIR/..")"
TOOLCHAIN_ID="${EIRINCHAN_TOOLCHAIN_ID:-elixir-1.20.2-otp-27}"
CACHE_ROOT="${EIRINCHAN_TEST_CACHE_ROOT:-${HOME}/.cache/eirinchan/test/${TOOLCHAIN_ID}}"

if [[ -n "${EIRINCHAN_TOOLCHAIN_PATH:-}" ]]; then
  export PATH="${EIRINCHAN_TOOLCHAIN_PATH}:${PATH}"
fi

export MIX_HOME="${MIX_HOME:-${HOME}/.mix}"
export HEX_HOME="${HEX_HOME:-${HOME}/.hex}"

if [[ -n "${EIRINCHAN_TEST_ENV_FILE:-}" ]]; then
  [[ -r "${EIRINCHAN_TEST_ENV_FILE}" ]] || {
    echo "EIRINCHAN_TEST_ENV_FILE is not readable; refusing to run tests." >&2
    exit 1
  }

  # shellcheck disable=SC1090
  source "${EIRINCHAN_TEST_ENV_FILE}"
fi

TEST_DATABASE_URL="${TEST_DATABASE_URL:-${AUTH_TEST_DATABASE_URL:-}}"

if [[ -z "${TEST_DATABASE_URL}" ]]; then
  echo "TEST_DATABASE_URL is missing; refusing to run tests." >&2
  exit 1
fi

if [[ -n "${DATABASE_URL:-}" && "${DATABASE_URL}" == "${TEST_DATABASE_URL}" ]]; then
  echo "TEST_DATABASE_URL matches DATABASE_URL; refusing to run tests." >&2
  exit 1
fi

export TEST_DATABASE_URL
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
