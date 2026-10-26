#!/usr/bin/env bash
# Apply to a newly copied, still-private release tree before publishing it.
set -euo pipefail

RELEASE_TREE="${1:?Usage: release-permissions.sh RELEASE_TREE SERVICE_GROUP}"
SERVICE_GROUP="${2:?A service group is required}"

[[ "$EUID" -eq 0 ]] || { echo "Release ownership must be applied as root." >&2; exit 1; }
[[ -d "$RELEASE_TREE" && ! -L "$RELEASE_TREE" && "$RELEASE_TREE" != / ]] || {
  echo "Expected a release directory, not a symlink or filesystem root." >&2; exit 1;
}
[[ -f "$RELEASE_TREE/bin/eirinchan" ]] || { echo "Not an Eirinchan release." >&2; exit 1; }
[[ "$SERVICE_GROUP" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || { echo "Invalid service group." >&2; exit 1; }
getent group "$SERVICE_GROUP" >/dev/null

COOKIE="$RELEASE_TREE/releases/COOKIE"
[[ -d "$RELEASE_TREE/releases" && ! -L "$RELEASE_TREE/releases" && -f "$COOKIE" && ! -L "$COOKIE" ]] || {
  echo "Expected a regular release cookie file in a real releases directory." >&2; exit 1;
}

# Keep the staging root private until every descendant, including the secret,
# has its final permissions. Never include COOKIE in the public artifact rule.
chmod 0700 "$RELEASE_TREE"
chown -R root:root "$RELEASE_TREE"
chown "root:$SERVICE_GROUP" "$COOKIE"
chmod 0640 "$COOKIE"
find "$RELEASE_TREE" -type f ! -path "$COOKIE" -perm /111 -exec chmod 0555 {} +
find "$RELEASE_TREE" -type f ! -path "$COOKIE" ! -perm /111 -exec chmod 0444 {} +
find "$RELEASE_TREE" -type d -exec chmod 0555 {} +
