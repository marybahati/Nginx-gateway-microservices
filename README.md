# Nginx Gateway Microservices

Three Node.js HTTP microservices behind an Nginx reverse proxy on Ubuntu 24.04 LTS. Only **Service A** is publicly reachable through Nginx on port 80.

| Host OS | Guide |
|---|---|
| macOS | [docs/setup-macos.md](docs/setup-macos.md) |
| Linux | [docs/setup-linux.md](docs/setup-linux.md) |
| Windows | [docs/setup-windows.md](docs/setup-windows.md) |

## Quick start

Inside the VM (`bahati@nginx-microservices`):

```bash
cd ~/nginx-microservices/Nginx-gateway-microservices
chmod +x install.sh uninstall.sh healthcheck.sh
sudo ./install.sh
make test
```

## Architecture

```
Client → Nginx (:80) → Service A (:3001) → Service B (:3002) → Service C (:3003)
                                                              ↘ POST /greeting-rcvd ↗
```

| Service | Port | Hostname | Via Nginx |
|---|---|---|---|
| Service A | 3001 | `service-a.internal` | Yes — `/service-a/*` |
| Service B | 3002 | `service-b.internal` | No |
| Service C | 3003 | `service-c.internal` | No |

## API contract

### Service A (`service-a`, port 3001)

| Method | Path | Response |
|---|---|---|
| GET | `/health` | `{ "service": "service-a", "status": "healthy", "port": 3001, "message": "..." }` |
| GET | `/greet-service-b` | `{ "request_id": "...", "status": "success", "message": "Request completed successfully" }` |
| POST | `/greeting-rcvd` | `{ "status": "received" }` — callback body from Service C |

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

### Request flow

`Client → Nginx → Service A → Service B → Service C → Service A callback`

The same `X-Request-ID` is propagated through every hop. Service A generates a UUID when the header is missing.

### Validation

```bash
curl http://localhost/service-a/health
curl http://service-b.internal:3002/health
curl http://service-c.internal:3003/health
curl http://localhost/service-a/greet-service-b
```

Trace a single `request_id` across:

```bash
sudo tail /var/log/nginx/nginx-gateway-access.log
journalctl -u service-a -u service-b -u service-c --since "5 min ago"
```

## Service discovery

Services communicate by **hostname only** — never hardcoded IPs in application or Nginx config.

| Caller | URL |
|---|---|
| Service A → B | `http://service-b.internal:3002` |
| Service B → C | `http://service-c.internal:3003` |
| Service C → A | `http://service-a.internal:3001` |
| Nginx → A | `http://service-a.internal:3001` |

**Mechanism:** `install.sh` writes static entries to `/etc/hosts`:

```
127.0.0.1 service-a.internal service-b.internal service-c.internal
```

**Resolution:** the Linux resolver (`/etc/nsswitch.conf` → `files`) looks up `*.internal` in `/etc/hosts` via `getent hosts`.

**Troubleshooting:**

```bash
getent hosts service-b.internal
systemctl status service-a service-b service-c
journalctl -u service-c -n 30
sudo ./install.sh    # re-apply /etc/hosts entries
```

## Reverse proxy (Nginx)

Nginx is the only public entry point on port 80.

1. `GET /service-a/health` hits Nginx → proxied to `service-a.internal:3001/health`
2. Nginx sets `X-Request-ID` (from client or generated via `$request_id`)
3. No `location` blocks exist for Service B or C — direct requests to `/service-b/` or `/service-c/` return **404**

Config files:

| Repo file | Installed to |
|---|---|
| `nginx/nginx-gateway-logging.conf` | `/etc/nginx/conf.d/` |
| `nginx/nginx-vm.conf` | `/etc/nginx/sites-available/nginx-gateway-microservices` |

```bash
nginx -T | grep -A5 'location /service-a'
make nginx-logs
```

## Logging

All services emit structured JSON to journald. Every log entry includes: `timestamp`, `service`, `event`, `request_id`, `path`, `status`.

Nginx writes JSON access logs to `/var/log/nginx/nginx-gateway-access.log` with `request_id`, `method`, `path`, `status`, `upstream` (`service-a:3001`), and `request_time`.

## Common operations

```bash
make help
make status
make logs
make nginx-logs
make restart
sudo ./uninstall.sh
```

## Repository structure

```
├── service.yaml          # Lima VM config (macOS)
├── install.sh
├── uninstall.sh
├── healthcheck.sh
├── Makefile
├── nginx/
├── systemd/
├── shared/logger.js
└── services/
    ├── service-a/
    ├── service-b/
    └── service-c/
```
