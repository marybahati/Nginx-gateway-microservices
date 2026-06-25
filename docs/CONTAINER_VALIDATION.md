# Container Validation

Validation evidence for the Docker Compose migration. All tests were run on macOS with Docker Desktop.

**Branch:** `feat/docker`  
**Date:** 2026-06-25

## Prerequisites

**Docker must be installed and running locally** before running these tests. Use Docker Compose V2 (`docker compose`); Docker Engine 20.10+ and Compose plugin 2.1+ recommended.

| Platform | Guide |
|---|---|
| macOS | [setup-macos.md](setup-macos.md) |
| Linux | [setup-linux.md](setup-linux.md) |
| Windows | [setup-windows.md](setup-windows.md) |

## Restart policy

Each application service uses `restart: unless-stopped`. Containers restart automatically after a host reboot or Docker daemon restart, but stay stopped if you explicitly run `docker compose stop`. This mirrors production "keep running unless intentionally shut down" without fighting manual debugging sessions.

---

## 1. Start the system

```bash
docker compose up --build -d
```

```
 Network nginx-gateway-microservices_gateway  Created
 Container nginx-gateway-microservices-service-b-1  Started
 Container nginx-gateway-microservices-service-c-1  Started
 Container nginx-gateway-microservices-service-a-1  Started
 Container nginx-gateway-microservices-nginx-1  Started
```

---

## 2. Confirm containers are running

```bash
docker compose ps
```

```
NAME                                      IMAGE                                   COMMAND                  SERVICE     STATUS          PORTS
nginx-gateway-microservices-nginx-1       nginx:1.27-alpine                       "/docker-entrypoint.…"   nginx       Up              0.0.0.0:8080->80/tcp
nginx-gateway-microservices-service-a-1   nginx-gateway-microservices-service-a   "docker-entrypoint.s…"   service-a   Up
nginx-gateway-microservices-service-b-1   nginx-gateway-microservices-service-b   "docker-entrypoint.s…"   service-b   Up
nginx-gateway-microservices-service-c-1   nginx-gateway-microservices-service-c   "docker-entrypoint.s…"   service-c   Up
```

All four services are running. Only Nginx publishes a host port (`8080:80`).

---

## 3. Test public entry point

```bash
curl -i http://localhost:8080/service-a/health
```

```
HTTP/1.1 200 OK
Server: nginx/1.27.5
Content-Type: application/json; charset=utf-8

{"service":"service-a","status":"healthy","port":3001,"message":"Hello service-a listening on 3001"}
```

Full flow:

```bash
curl -i http://localhost:8080/service-a/greet-service-b
```

```
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"request_id":"<uuid>","status":"success","message":"Request completed successfully"}
```

---

## 4. Prove B and C are not directly exposed

From the host:

```bash
curl -i --connect-timeout 3 http://localhost:3002/health
curl -i --connect-timeout 3 http://localhost:3003/health
```

```
curl: (7) Failed to connect to localhost port 3002 after 0 ms: Couldn't connect to server
curl: (7) Failed to connect to localhost port 3003 after 0 ms: Couldn't connect to server
```

Connection refused — ports 3002 and 3003 are not published to the host.

Nginx also returns 404 for direct B/C routes:

```bash
curl -i http://localhost:8080/service-b/health   # 404
curl -i http://localhost:8080/service-c/health   # 404
```

---

## 5. Prove internal service discovery works

From inside the Docker Compose network:

```bash
docker compose exec service-a node -e "fetch('http://service-b:3002/health').then(r=>r.json()).then(console.log)"
docker compose exec service-b node -e "fetch('http://service-c:3003/health').then(r=>r.json()).then(console.log)"
```

```
HTTP/1.1 200 OK
{"service":"service-b","status":"healthy","port":3002,"message":"Hello service-b listening on 3002"}

HTTP/1.1 200 OK
{"service":"service-c","status":"healthy","port":3003,"message":"Hello service-c listening on 3003"}
```

Services communicate using Compose DNS names (`service-b`, `service-c`), not `localhost`.

---

## 6. Trace one request

```bash
curl -i http://localhost:8080/service-a/greet-service-b \
  -H "X-Request-ID: demo-container-001"

docker compose logs | grep demo-container-001
```

```
HTTP/1.1 200 OK
{"request_id":"demo-container-001","status":"success","message":"Request completed successfully"}
```

Log grep output (same request ID in all four services):

```
service-a-1  | {"timestamp":"...","service":"service-a","event":"request_received","request_id":"demo-container-001",...}
service-a-1  | {"timestamp":"...","service":"service-a","event":"request_forwarded","request_id":"demo-container-001","target":"service-b",...}
service-a-1  | {"timestamp":"...","service":"service-a","event":"callback_received","request_id":"demo-container-001","source_service":"service-c",...}
service-a-1  | {"timestamp":"...","service":"service-a","event":"request_completed","request_id":"demo-container-001",...}
service-b-1  | {"timestamp":"...","service":"service-b","event":"request_received","request_id":"demo-container-001","path":"/greet",...}
service-b-1  | {"timestamp":"...","service":"service-b","event":"request_forwarded","request_id":"demo-container-001","target":"service-c",...}
service-c-1  | {"timestamp":"...","service":"service-c","event":"request_received","request_id":"demo-container-001","path":"/greet-c",...}
service-c-1  | {"timestamp":"...","service":"service-c","event":"callback_sent","request_id":"demo-container-001","target":"service-a",...}
nginx-1      | {"timestamp":"...","request_id":"demo-container-001","method":"GET","path":"/service-a/greet-service-b","status":200,...}
```

---

## 7. Stop Service B and observe failure

```bash
docker compose stop service-b

curl -i http://localhost:8080/service-a/greet-service-b \
  -H "X-Request-ID: fail-service-b-001"
```

```
HTTP/1.1 500 Internal Server Error
Content-Type: application/json; charset=utf-8

{"request_id":"fail-service-b-001","status":"error","message":"fetch failed"}
```

Service A logs the failure:

```bash
docker compose logs service-a | grep fail-service-b-001
```

```
service-a-1  | {"timestamp":"...","service":"service-a","event":"request_received","request_id":"fail-service-b-001","path":"/greet-service-b",...}
service-a-1  | {"timestamp":"...","service":"service-a","event":"request_failed","request_id":"fail-service-b-001","path":"/greet-service-b","status":500,"error":"fetch failed"}
```

**Recover:**

```bash
docker compose start service-b

curl -i http://localhost:8080/service-a/greet-service-b \
  -H "X-Request-ID: recover-001"
```

```
HTTP/1.1 200 OK
{"request_id":"recover-001","status":"success","message":"Request completed successfully"}
```

Unlike a systemd `Requires=` coupling, stopping Service B in Docker does **not** stop Service A. Service A stays running and returns a clear **500** error until B is restarted.

**If you see 502 instead of 500** after stopping/starting containers, Nginx may be using a stale `service-a` IP (classic Docker + Nginx DNS caching). Check `docker compose logs nginx` for `connect() failed (111: Connection refused)`. The repo config uses `resolver 127.0.0.11` and `server … resolve` in `nginx/nginx-docker.conf` so Nginx re-resolves `service-a` every ~10s. After updating that file, run `docker compose restart nginx` once, then confirm all services are up with `docker compose ps`.

---

## Quick validation

Run all 7 checks in one command:

```bash
make test
```

```
=== [1/7] Containers running ===
OK: all four services running

=== [2/7] Service A via Nginx (:8080) ===
{ "service": "service-a", "status": "healthy", ... }

=== [3/7] Service B not exposed from host ===
OK: connection refused or timed out

=== [4/7] Service C not exposed from host ===
OK: connection refused or timed out

=== [5/7] Internal discovery ===
{ "service": "service-b", "status": "healthy", ... }
{ "service": "service-c", "status": "healthy", ... }

=== [6/7] Request tracing ===
{ "request_id": "make-docker-test-trace", "status": "success", ... }
OK: request ID found in logs

=== [7/7] Stop Service B, observe failure, recover ===
OK: request failed while B is down
OK: failure logged by service-a
{ "request_id": "make-recover-001", "status": "success", ... }

All Docker validation commands succeeded.
```
