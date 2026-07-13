#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this installer as root." >&2
  exit 1
fi

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

apt-get update
apt-get install -y dehydrated

install -d -m 0755 /etc/dehydrated /usr/local/libexec
install -m 0644 "$SOURCE_DIR/dehydrated.conf" /etc/dehydrated/eirinchan.conf
install -m 0644 "$SOURCE_DIR/domains.txt" /etc/dehydrated/eirinchan-domains.txt
install -m 0755 "$SOURCE_DIR/eirinchan-cert-hook" /usr/local/libexec/eirinchan-cert-hook
install -m 0644 "$SOURCE_DIR/eirinchan-cert-renew.service" /etc/systemd/system/eirinchan-cert-renew.service
install -m 0644 "$SOURCE_DIR/eirinchan-cert-renew.timer" /etc/systemd/system/eirinchan-cert-renew.timer

install -d -m 0700 -o telemazer -g telemazer /home/telemazer/phoenix-gateway/var/acme
install -d -m 0700 -o telemazer -g telemazer /home/telemazer/phoenix-gateway/var/certs
install -d -m 0700 /var/lib/dehydrated

systemctl disable --now certbot.timer 2>/dev/null || true
systemctl daemon-reload
dehydrated --register --accept-terms --config /etc/dehydrated/eirinchan.conf
systemctl enable --now eirinchan-cert-renew.timer
systemctl start eirinchan-cert-renew.service
