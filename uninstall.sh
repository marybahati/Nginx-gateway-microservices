#!/usr/bin/env bash
#
# uninstall.sh — Tear down the nginx-gateway-microservices environment.
#
set -Eeuo pipefail

LAB_USER="microsvc"
LAB_HOME="/opt/nginx-gateway-microservices"
HOSTS_MARKER="nginx-gateway-microservices"
SERVICES=(service-a service-b service-c)

log() { printf '\033[1;36m[uninstall]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[uninstall:err]\033[0m %s\n' "$*" >&2; exit 1; }

trap 'die "uninstall.sh failed at line $LINENO"' ERR

[[ $EUID -eq 0 ]] || die "Must run as root. Try: sudo $0"

log "Stopping + disabling microservices"
for svc in "${SERVICES[@]}"; do
  systemctl stop "$svc" >/dev/null 2>&1 || true
  systemctl disable "$svc" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/${svc}.service"
done
systemctl daemon-reload
systemctl reset-failed >/dev/null 2>&1 || true

log "Removing Nginx site configuration"
rm -f /etc/nginx/sites-enabled/nginx-gateway-microservices
rm -f /etc/nginx/sites-available/nginx-gateway-microservices
rm -f /etc/nginx/conf.d/nginx-gateway-logging.conf
rm -f /var/log/nginx/nginx-gateway-access.log
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t && systemctl reload nginx || true

log "Removing service discovery entries"
sed -i "/nginx-gateway-microservices/d" /etc/hosts 2>/dev/null || true

log "Removing $LAB_HOME"
rm -rf "$LAB_HOME"

if id -u "$LAB_USER" >/dev/null 2>&1; then
  log "Removing user '$LAB_USER'"
  userdel "$LAB_USER" || true
fi

log "Uninstall complete."
