#!/usr/bin/env bash
# Local disposable Linux fixture only. Does not execute the deployment script.
set -euo pipefail
[[ "$EUID" -eq 0 ]] || { echo "Run in an isolated root-owned test environment." >&2; exit 1; }
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
FIXTURE="$(mktemp -d /tmp/eirinchan-release-permissions.XXXXXX)"
trap 'rm -rf -- "$FIXTURE"' EXIT
chmod 0755 "$FIXTURE"
TREE="$FIXTURE/release"
mkdir -p "$TREE/bin" "$TREE/releases" "$TREE/lib"
touch "$TREE/bin/eirinchan" "$TREE/releases/COOKIE" "$TREE/lib/example.beam"
chmod 0755 "$TREE/bin/eirinchan"
chmod 0644 "$TREE/lib/example.beam"

bash "$REPO/ops/deploy/release-permissions.sh" "$TREE" nogroup
[[ "$(stat -c '%U:%G:%a' "$TREE/releases/COOKIE")" == root:nogroup:640 ]]
[[ "$(stat -c '%U:%G:%a' "$TREE/lib/example.beam")" == root:root:444 ]]
[[ "$(stat -c '%a' "$TREE/bin/eirinchan")" == 555 ]]
[[ "$(stat -c '%a' "$TREE")" == 555 ]]
runuser -u nobody -- test -r "$TREE/releases/COOKIE"
! runuser -u daemon -- test -r "$TREE/releases/COOKIE"
! runuser -u nobody -- test -w "$TREE/lib/example.beam"
! runuser -u nobody -- test -w "$TREE/releases/COOKIE"
runuser -u daemon -- test -r "$TREE/lib/example.beam"

# Secret symlinks and incomplete trees must fail closed before broad chmods.
rm "$TREE/releases/COOKIE"
ln -s "$TREE/lib/example.beam" "$TREE/releases/COOKIE"
! bash "$REPO/ops/deploy/release-permissions.sh" "$TREE" nogroup
rm "$TREE/releases/COOKIE"
! bash "$REPO/ops/deploy/release-permissions.sh" "$TREE" nogroup
mv "$TREE/releases" "$FIXTURE/elsewhere"
ln -s "$FIXTURE/elsewhere" "$TREE/releases"
! bash "$REPO/ops/deploy/release-permissions.sh" "$TREE" nogroup
for script in install-release.sh release-permissions.sh; do
  bash -n "$REPO/ops/deploy/$script"
done
printf 'Release permission fixture: passed\n'
