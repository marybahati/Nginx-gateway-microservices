# Nginx Gateway Microservices

A production-style microservice environment on Ubuntu 24.04 LTS: three Node.js HTTP services behind an Nginx reverse proxy, managed by systemd, with service discovery, structured logging, request tracing, and network isolation for internal services.

Only **Service A** is publicly reachable through Nginx on port 80. Services B and C are internal infrastructure.

| Host OS | Guide |
|---|---|
| macOS | [docs/setup-macos.md](docs/setup-macos.md) |
| Linux | [docs/setup-linux.md](docs/setup-linux.md) |
| Windows | [docs/setup-windows.md](docs/setup-windows.md) |

## Project overview

The system demonstrates operational patterns used in production:

- **Linux service management** — all services run under systemd with boot-time start and automatic restart
- **Service discovery** — services communicate by hostname (`*.internal`), not hardcoded IPs
- **Reverse proxy** — Nginx is the sole public entry point
- **Network security** — internal services bind to loopback and are blocked by firewall rules
- **Dependency management** — Service A waits for B and C to be healthy before starting
- **Structured logging** — JSON logs to journald and Nginx access logs
- **Request tracing** — a single `X-Request-ID` propagates through every hop

## Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │              Ubuntu VM                      │
  Client ──────────►│  Nginx (:80)                                │
  (public)          │       │                                     │
                    │       ▼                                     │
                    │  Service A (:3001)  service-a.internal      │
                    │       │                                     │
                    │       ▼                                     │
                    │  Service B (:3002)  service-b.internal      │
                    │       │                                     │
                    │       ▼                                     │
                    │  Service C (:3003)  service-c.internal      │
                    │       │                                     │
                    │       └──── POST /greeting-rcvd ────────────┘
                    └─────────────────────────────────────────────┘
```

| Service | Port | Hostname | Public access |
|---|---|---|---|
| Nginx | 80 | VM public IP | Yes — only entry point |
| Service A | 3001 | `service-a.internal` | Via Nginx only (`/service-a/*`) |
| Service B | 3002 | `service-b.internal` | No — loopback + firewall |
| Service C | 3003 | `service-c.internal` | No — loopback + firewall |

### Request flow

`Client → Nginx → Service A → Service B → Service C → Service A (callback)`

A user hits `GET /service-a/greet-service-b` via Nginx. Service A calls B, B forwards to C, and C callbacks to A.

| Step | Endpoint | What happens |
|---|---|---|
| 1 | `GET /service-a/greet-service-b` (via Nginx) | User starts the full flow |
| 2 | A → `service-b.internal:3002/greet` | Service A calls Service B |
| 3 | B → `service-c.internal:3003/greet-c` | Service B forwards to Service C |
| 4 | C → `service-a.internal:3001/greeting-rcvd` | Service C callbacks to Service A |
| 5 | Response to client | Service A returns success |

The same `X-Request-ID` is propagated through every hop. Service A generates a UUID when the header is missing.

## Installation

Prerequisites: Ubuntu 24.04 LTS VM with `sudo` access.

```bash
cd ~/nginx-microservices/Nginx-gateway-microservices
chmod +x install.sh uninstall.sh healthcheck.sh scripts/*.sh
sudo ./install.sh
```

`install.sh` performs:

1. Installs nginx, Node.js, ufw, and utilities
2. Copies the application to `/opt/nginx-gateway-microservices`
3. Writes `/etc/hosts` entries for service discovery
4. Configures ufw (allow 80 + SSH; deny 3001–3003)
5. Installs systemd units and Nginx site config
6. Starts Service B and C, then Service A (with health wait)

Verify:

```bash
make test
./healthcheck.sh
```

## Operation

### Start

```bash
sudo systemctl start service-b service-c   # dependencies first
sudo systemctl start service-a
sudo systemctl start nginx
# or:
make start
```

### Stop

```bash
sudo systemctl stop nginx service-a service-b service-c
# or:
make stop
```

### Restart

```bash
make restart
# individual service:
sudo systemctl restart service-b
```

### Verify health

```bash
make test
./healthcheck.sh
curl http://localhost/service-a/health
curl http://service-b.internal:3002/health   # from inside VM only
curl http://service-c.internal:3003/health
curl http://localhost/service-a/greet-service-b
```

### Shutdown (full removal)

```bash
sudo ./uninstall.sh
```

## Validation

End-to-end smoke test:

```bash
make test
```

Manual checks:

```bash
# Public path works
curl http://localhost/service-a/health

# Full request chain
curl http://localhost/service-a/greet-service-b

# Internal services reachable on loopback (from VM)
curl http://service-b.internal:3002/health
curl http://service-c.internal:3003/health

# Internal services NOT reachable via public IP (replace with VM IP)
curl --max-time 3 http://<VM_PUBLIC_IP>:3002/health   # should fail / timeout
curl --max-time 3 http://<VM_PUBLIC_IP>:3003/health   # should fail / timeout

# Nginx does not proxy B or C
curl http://localhost/service-b/health   # 404
curl http://localhost/service-c/health   # 404
```

Reboot recovery:

```bash
sudo reboot
# after VM is back:
make status
make test
```

## Service discovery

Services communicate by **hostname only** — never hardcoded IPs in application or Nginx config.

| Caller | URL |
|---|---|
| Service A → B | `http://service-b.internal:3002` |
| Service B → C | `http://service-c.internal:3003` |
| Service C → A | `http://service-a.internal:3001` |
| Nginx → A | `http://service-a.internal:3001` |

### How services discover one another

`install.sh` registers static hostnames in `/etc/hosts`:

```
127.0.0.1 service-a.internal service-b.internal service-c.internal
```

Each service reads peer URLs from environment variables set in its systemd unit (e.g. `SERVICE_B_URL=http://service-b.internal:3002`).

### How name resolution works

1. Application calls `http://service-b.internal:3002`
2. The Linux resolver consults `/etc/nsswitch.conf` (typically `files` first)
3. `/etc/hosts` maps `service-b.internal` → `127.0.0.1`
4. The connection goes to the local Service B process on port 3002

Verify: `getent hosts service-b.internal`

### What component performs resolution

The **Linux glibc resolver** (`getent hosts`, used by Node.js `fetch`) performs lookup via `/etc/hosts`. Nginx resolves upstream hostnames the same way at request time.

### Troubleshooting discovery failures

```bash
getent hosts service-b.internal          # should return 127.0.0.1
cat /etc/hosts | grep nginx-gateway      # entries present?
sudo ./install.sh                        # re-apply hosts entries
systemctl status service-b
journalctl -u service-b -n 30
curl -v http://service-b.internal:3002/health
```

## Reverse proxy (Nginx)

Nginx is the only public entry point on port 80.

**Traffic flow:**

1. Client sends `GET /service-a/health` to Nginx on port 80
2. Nginx matches `location /service-a/` and proxies to upstream `service_a`
3. Upstream resolves `service-a.internal:3001` and forwards the request
4. Nginx sets `X-Request-ID` (from client header or auto-generated `$request_id`)
5. Response returns to the client

No `location` blocks exist for Service B or C — requests to `/service-b/` or `/service-c/` return **404**.

Config files:

| Repo file | Installed to |
|---|---|
| `nginx/nginx-gateway-logging.conf` | `/etc/nginx/conf.d/` |
| `nginx/nginx-vm.conf` | `/etc/nginx/sites-available/nginx-gateway-microservices` |

```bash
nginx -T | grep -A5 'location /service-a'
make nginx-logs
```

## Network security

### Why services are protected

Service B and C are **internal infrastructure**. They should only be called by other services on the same VM, not by external clients. Exposing them would bypass Service A's logging, tracing, and access controls.

### What enforces protection

Two layers (defense in depth):

1. **Socket binding** — Services B and C bind to `127.0.0.1` only (`BIND_HOST=127.0.0.1`). They do not listen on the VM's external network interface.
2. **Firewall (ufw)** — `install.sh` enables ufw with:
   - Allow: SSH, port 80 (Nginx)
   - Deny: ports 3001, 3002, 3003

Service A is also bound to loopback; it is reachable publicly only through Nginx on port 80.

### How to verify protection

```bash
# From inside the VM — should work
curl http://service-b.internal:3002/health

# From outside the VM (replace with public IP) — should fail
curl --max-time 3 http://<VM_PUBLIC_IP>:3002/health
curl --max-time 3 http://<VM_PUBLIC_IP>:3003/health

# Confirm bind addresses
ss -tlnp | grep -E '300[123]'

# Confirm firewall
sudo ufw status
```

`./healthcheck.sh` includes an automated external-access check when a public IP is detectable.

### Troubleshooting connectivity issues

| Symptom | Check |
|---|---|
| Can't reach Service A via Nginx | `systemctl status nginx`, `nginx -t`, `curl localhost/service-a/health` |
| Internal service unreachable from VM | `getent hosts`, `systemctl status service-b`, `ss -tlnp \| grep 3002` |
| Unexpected external access | `ss -tlnp` (should show `127.0.0.1:3002`), `ufw status` |
| Service A can't reach B | Discovery (`getent hosts`), B health (`curl service-b.internal:3002/health`) |

## Service lifecycle (systemd)

All services are managed by systemd:

| Requirement | Implementation |
|---|---|
| Start on boot | `systemctl enable` in `install.sh`; `WantedBy=multi-user.target` |
| Restart on failure | `Restart=on-failure`, `RestartSec=3s` |
| Structured logs | `StandardOutput=journal`, `StandardError=journal` |
| Standard commands | `systemctl start\|stop\|restart\|status service-a` |

```bash
systemctl status service-a service-b service-c nginx
journalctl -u service-a -f
journalctl -u service-a -u service-b -u service-c --since "10 min ago"
```

## Dependency management

Service A depends on Service B and Service C.

| Requirement | Implementation |
|---|---|
| A starts after B and C | `After=service-b.service service-c.service` |
| A stops if B or C stops | `Requires=service-b.service service-c.service` |
| A waits until B/C are healthy | `ExecStartPre=wait-for-deps.sh` polls `/health` |

Boot order: `service-b` → `service-c` → `service-a` → `nginx`.

If an instructor stops service B:
**Stopping B also stops A:** `Requires=` tells systemd that A cannot run without B/C. Stopping B stops A too.

**Recovery:** starting B alone is not enough — A must be started again as well.

```bash
sudo systemctl stop service-b
systemctl is-active service-a service-b    # both inactive

curl http://localhost/service-a/greet-service-b   # 502 (A is down)

sudo systemctl start service-b service-a            # start both
curl http://localhost/service-a/greet-service-b   # success
journalctl -u service-a -n 10                       # shows recovery
```

## Request tracing

Every request carries an `X-Request-ID` header through the full chain:

| Hop | Mechanism |
|---|---|
| Nginx | `map $http_x_request_id $req_id` — uses client header or `$request_id` |
| Service A | Reads/generates UUID; forwards to B |
| Service B | Forwards same header to C |
| Service C | Forwards same header on callback to A |

Trace a single request:

```bash
# Trigger a request and note the request_id in the response
curl http://localhost/service-a/greet-service-b

# Follow it across all services
REQUEST_ID="<uuid-from-response>"
journalctl -u service-a -u service-b -u service-c --since "5 min ago" | grep "$REQUEST_ID"
sudo grep "$REQUEST_ID" /var/log/nginx/nginx-gateway-access.log
```

## Logging

### Application logs (journald)

All services emit structured JSON to stdout, captured by journald:

```json
{"timestamp":"2026-06-18T12:00:00.000Z","service":"service-a","event":"request_received","request_id":"abc-123","method":"GET","path":"/health","status":200}
```

Fields answer: **what** (`event`), **when** (`timestamp`), **which service** (`service`), **which request** (`request_id`), **outcome** (`status`).

```bash
journalctl -u service-a -u service-b -u service-c --since "1 hour ago"
journalctl -u service-c -n 50 --no-pager
make logs
```

### Nginx access logs

JSON access log at `/var/log/nginx/nginx-gateway-access.log`:

```bash
make nginx-logs
sudo tail -20 /var/log/nginx/nginx-gateway-access.log | jq .
```

## Error handling

Invalid routes return **404** with a JSON body and a structured log entry (`event: route_not_found`). Downstream failures return **500** or **504** with `event: request_failed` and the `request_id` for correlation.

```bash
curl -i http://localhost/service-a/nonexistent
curl -i http://localhost/service-b/health   # 404 from Nginx (not proxied)
```

## Troubleshooting guide

### Service startup failures

```bash
systemctl status service-a
journalctl -u service-a -n 50 --no-pager
ls -la /opt/nginx-gateway-microservices/services/service-a/
```

Common causes: missing npm deps (`sudo ./install.sh`), port in use (`ss -tlnp | grep 3001`), dependency wait timeout (B/C not healthy).

### Service dependency failures

```bash
systemctl status service-b service-c
/opt/nginx-gateway-microservices/scripts/wait-for-deps.sh   # manual run
journalctl -u service-a | grep -i dependency
```

### Reverse proxy failures

```bash
systemctl status nginx
nginx -t
tail -20 /var/log/nginx/error.log
curl -v http://localhost/service-a/health
```

### Service discovery / name resolution failures

```bash
getent hosts service-b.internal
grep nginx-gateway /etc/hosts
sudo ./install.sh   # re-apply
```

### Network access failures

```bash
ss -tlnp | grep -E '80|300[123]'
sudo ufw status
curl -v http://127.0.0.1:3002/health
curl -v http://service-b.internal:3002/health
```

### Missing logs

```bash
journalctl -u service-a --since today
ls -la /var/log/nginx/nginx-gateway-access.log
# Ensure service is running and handling requests
```

### Invalid routing behavior

```bash
nginx -T | grep -A10 'location'
curl -i http://localhost/service-b/health    # expect 404
curl -i http://localhost/service-a/health   # expect 200
```

### Inter-service communication failures

```bash
# Stop B, trigger flow, check logs
sudo systemctl stop service-b
curl http://localhost/service-a/greet-service-b   # 502 — A stopped too (Requires=)
sudo systemctl start service-b service-a          # recovery needs both
curl http://localhost/service-a/greet-service-b
journalctl -u service-a -n 10
```

## Common operations

```bash
make help
make status
make logs
make nginx-logs
make restart
make test
sudo ./uninstall.sh
```

## API contract

### Service A (`service-a`, port 3001)

| Method | Path | Response |
|---|---|---|
| GET | `/health` | `{ "service": "service-a", "status": "healthy", "port": 3001, "message": "..." }` |
| GET | `/greet-service-b` | `{ "request_id": "...", "status": "success", "message": "Request completed successfully" }` |
| POST | `/greeting-rcvd` | `{ "status": "received" }` — callback from Service C |

### Service B (`service-b`, port 3002, internal)

| Method | Path | Response |
|---|---|---|
| GET | `/health` | `{ "service": "service-b", "status": "healthy", "port": 3002, "message": "..." }` |
| GET | `/greet` | `{ "request_id": "...", "status": "forwarded", "target": "service-c" }` — requires `X-Request-ID` |

### Service C (`service-c`, port 3003, internal)

| Method | Path | Response |
|---|---|---|
| GET | `/health` | `{ "service": "service-c", "status": "healthy", "port": 3003, "message": "..." }` |
| GET | `/greet-c` | `{ "request_id": "...", "status": "processed", "callback_sent": true }` — requires `X-Request-ID` |

## Repository structure

```
├── service.yaml              # Lima VM config (macOS)
├── install.sh                # Deployment bootstrap
├── uninstall.sh              # Teardown
├── healthcheck.sh            # Operational snapshot
├── Makefile                  # Common commands
├── scripts/
│   └── wait-for-deps.sh      # Service A dependency health wait
├── nginx/
│   ├── nginx-vm.conf
│   └── nginx-gateway-logging.conf
├── systemd/
│   ├── service-a.service
│   ├── service-b.service
│   └── service-c.service
├── shared/logger.js
└── services/
    ├── service-a/
    ├── service-b/
    └── service-c/
```
