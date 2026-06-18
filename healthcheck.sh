#!/usr/bin/env bash
#
# healthcheck.sh — Print a system + service snapshot for nginx-gateway-microservices.
#
set -Eeuo pipefail

SERVICES=(service-a service-b service-c nginx)

bold()    { printf '\033[1m%s\033[0m\n' "$*"; }
section() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
kv()      { printf '  %-18s %s\n' "$1" "$2"; }

section "System"
kv "Hostname"     "$(hostname)"
kv "Kernel"       "$(uname -srm)"
kv "Distro"       "$(lsb_release -ds 2>/dev/null || echo 'unknown')"
kv "Uptime"       "$(uptime -p)"
kv "Load average" "$(awk '{print $1, $2, $3}' /proc/loadavg)"

section "Memory"
free -h | sed 's/^/  /'

section "Disk"
df -hT --total -x tmpfs -x devtmpfs | sed 's/^/  /'

section "Microservices"
for svc in "${SERVICES[@]}"; do
  if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
    state="$(systemctl is-active "$svc" 2>/dev/null || echo unknown)"
    sub="$(systemctl is-enabled "$svc" 2>/dev/null || echo unknown)"
    printf '  %-22s active=%-10s enabled=%s\n' "$svc" "$state" "$sub"
  else
    printf '  %-22s (not installed)\n' "$svc"
  fi
done

section "Listening ports"
if command -v ss >/dev/null 2>&1; then
  ss -tulnp 2>/dev/null | grep -E ':(80|3001|3002|3003)\s' | sed 's/^/  /' || echo "  (no matching ports)"
else
  netstat -tulnp 2>/dev/null | grep -E ':(80|3001|3002|3003)\s' | sed 's/^/  /' || true
fi

section "Network security (internal ports)"
PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -n "$PUBLIC_IP" ]]; then
  for port in 3002 3003; do
    if curl -sf --max-time 2 "http://${PUBLIC_IP}:${port}/health" >/dev/null 2>&1; then
      printf '  port %s via %s  EXPOSED (should be blocked)\n' "$port" "$PUBLIC_IP"
    else
      printf '  port %s via %s  blocked (expected)\n' "$port" "$PUBLIC_IP"
    fi
  done
else
  echo "  (could not determine public IP — run curl http://<vm-ip>:3002/health manually)"
fi

if command -v ufw >/dev/null 2>&1; then
  ufw status 2>/dev/null | sed 's/^/  /' || true
fi

section "API smoke tests"
for url in \
  "http://localhost/service-a/health" \
  "http://service-b.internal:3002/health" \
  "http://service-c.internal:3003/health"; do
  if curl -sf --max-time 3 "$url" >/dev/null; then
    printf '  %-45s OK\n' "$url"
  else
    printf '  %-45s FAIL\n' "$url"
  fi
done

section "Recent Nginx gateway access log"
if [[ -f /var/log/nginx/nginx-gateway-access.log ]]; then
  tail -n 3 /var/log/nginx/nginx-gateway-access.log | sed 's/^/  /'
else
  echo "  /var/log/nginx/nginx-gateway-access.log not found yet"
fi

echo
bold "healthcheck complete."
