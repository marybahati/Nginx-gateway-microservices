#!/usr/bin/env bash
#
# install.sh — Bootstrap nginx-gateway-microservices on Ubuntu 24.04 LTS.
#
# Installs system nginx, Node.js, copies the project to /opt, and enables
# systemd units for service-a, service-b, and service-c.
#
# Idempotent: safe to re-run. Fails loudly on any error.
#
set -Eeuo pipefail

LAB_USER="microsvc"
LAB_HOME="/opt/nginx-gateway-microservices"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVICES=(service-a service-b service-c)

log()  { printf '\033[1;36m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install:warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install:err]\033[0m %s\n' "$*" >&2; exit 1; }

trap 'die "install.sh failed at line $LINENO (command: $BASH_COMMAND)"' ERR

require_root() {
  [[ $EUID -eq 0 ]] || die "Must run as root. Try: sudo $0"
}

require_ubuntu_24_04() {
  if ! command -v lsb_release >/dev/null 2>&1; then
    warn "lsb_release missing — installing lsb-release"
    apt-get update -qq && apt-get install -y -qq lsb-release
  fi
  local id ver
  id="$(lsb_release -si)"
  ver="$(lsb_release -sr)"
  if [[ "$id" != "Ubuntu" || "$ver" != "24.04" ]]; then
    warn "Detected $id $ver — this lab targets Ubuntu 24.04 LTS. Continuing anyway."
  fi
}

install_packages() {
  log "Installing nginx, Node.js, and utilities"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    nginx nodejs npm curl jq make rsync ufw

  if ! command -v node >/dev/null 2>&1 && command -v nodejs >/dev/null 2>&1; then
    log "Linking nodejs → node"
    ln -sf /usr/bin/nodejs /usr/bin/node
  fi
}

ensure_user() {
  if id -u "$LAB_USER" >/dev/null 2>&1; then
    log "User '$LAB_USER' already exists"
  else
    log "Creating system user '$LAB_USER'"
    useradd --system --home-dir "$LAB_HOME" --shell /usr/sbin/nologin "$LAB_USER"
  fi
}

install_app() {
  log "Installing application into $LAB_HOME"
  install -d -o "$LAB_USER" -g "$LAB_USER" -m 0755 "$LAB_HOME"
  rsync -a --delete \
    --exclude node_modules \
    --exclude .git \
    "$REPO_DIR/" "$LAB_HOME/"

  for svc in "${SERVICES[@]}"; do
    log "Installing npm dependencies for $svc"
    (cd "$LAB_HOME/services/$svc" && npm install --omit=dev)
  done

  chown -R "$LAB_USER:$LAB_USER" "$LAB_HOME"
  chmod +x "$LAB_HOME/scripts/"*.sh
}

configure_service_discovery() {
  log "Configuring service discovery (/etc/hosts)"
  local marker="nginx-gateway-microservices"
  local entry="127.0.0.1 service-a.internal service-b.internal service-c.internal"
  if grep -q "$marker" /etc/hosts; then
    sed -i "/${marker}/d" /etc/hosts
  fi
  printf '%s  # %s\n' "$entry" "$marker" >> /etc/hosts
}

configure_firewall() {
  log "Configuring firewall (ufw) — block direct access to app ports"
  ufw --force reset >/dev/null 2>&1 || true
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw allow 80/tcp comment 'nginx-gateway-public'
  ufw deny 3001/tcp comment 'internal-service-a'
  ufw deny 3002/tcp comment 'internal-service-b'
  ufw deny 3003/tcp comment 'internal-service-c'
  ufw --force enable
}

install_nginx() {
  log "Installing Nginx site configuration"
  install -o root -g root -m 0644 \
    "$REPO_DIR/nginx/nginx-gateway-logging.conf" /etc/nginx/conf.d/nginx-gateway-logging.conf
  install -o root -g root -m 0644 \
    "$REPO_DIR/nginx/nginx-vm.conf" /etc/nginx/sites-available/nginx-gateway-microservices

  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/nginx-gateway-microservices \
    /etc/nginx/sites-enabled/nginx-gateway-microservices

  nginx -t
  systemctl enable nginx
  systemctl restart nginx
}

install_units() {
  log "Installing systemd unit files"
  for svc in "${SERVICES[@]}"; do
    install -o root -g root -m 0644 \
      "$REPO_DIR/systemd/${svc}.service" "/etc/systemd/system/${svc}.service"
  done
  systemctl daemon-reload
}

start_services() {
  for svc in service-b service-c; do
    log "Enabling + starting $svc"
    systemctl enable "$svc"
    systemctl restart "$svc"
  done
  log "Enabling + starting service-a (waits for B + C health)"
  systemctl enable service-a
  systemctl restart service-a
}

print_status() {
  log "--- Installed services status ---"
  systemctl --no-pager --full status nginx "${SERVICES[@]}" 2>&1 | sed 's/^/  /' || true
  log "Smoke test:"
  if curl -sf --max-time 5 http://localhost/service-a/health >/dev/null; then
    echo "  curl localhost/service-a/health → OK"
  else
    warn "  curl localhost/service-a/health did not respond — give services a few seconds, then run ./healthcheck.sh"
  fi
}

main() {
  require_root
  require_ubuntu_24_04
  install_packages
  ensure_user
  install_app
  configure_service_discovery
  configure_firewall
  install_units
  start_services
  install_nginx
  print_status
  log "Install complete. Run ./healthcheck.sh or make test to validate."
}

main "$@"
