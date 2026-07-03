# Setup — macOS (Docker Compose)

Goal: run the full Nginx gateway microservices stack on your Mac using Docker Compose. ~5 minutes from a clean machine.

**Docker must be installed and running locally.** This guide walks through installing Docker Desktop on macOS.

## 1. Host requirements

| Resource | Minimum |
|---|---|
| Docker | **Required** — [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/) (see below) |
| CPU | 2 cores |
| RAM | 4 GB free |
| Disk | 5 GB free for images |
| macOS | 13 Ventura or newer |
| Tools | Git and curl; `make` is optional but recommended |

## 2. Install Docker Desktop

```bash
brew install --cask docker
open -a Docker    # wait until the whale icon shows "Docker Desktop is running"
docker --version
docker compose version
```

Use **Docker Desktop 4.x or newer** (includes Docker Compose V2). Avoid the legacy `docker-compose` v1-only install.

If you don't have Homebrew: download [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/).

## 3. Clone the repository

```bash
mkdir -p ~/nginx-microservices
cd ~/nginx-microservices
git clone https://github.com/marybahati/Nginx-gateway-microservices.git Nginx-gateway-microservices
cd Nginx-gateway-microservices
```

## 4. Start the system

```bash
docker compose up --build -d
docker compose ps
```

Expected: four containers running — `nginx`, `service-a`, `service-b`, `service-c`.

## 5. Validate

```bash
make test
```

Or manually:

```bash
# Public entry point (Nginx is the only published port)
curl -fsS http://localhost:8080/service-a/health
curl -fsS http://localhost:8080/service-a/greet-service-b

# B and C are NOT reachable from the host
curl -fsS --connect-timeout 3 http://localhost:3002/health >/dev/null 2>&1 && echo "UNEXPECTED: service-b is exposed" || echo "OK: service-b is not exposed"
curl -fsS --connect-timeout 3 http://localhost:3003/health >/dev/null 2>&1 && echo "UNEXPECTED: service-c is exposed" || echo "OK: service-c is not exposed"

# Internal discovery works inside the network
docker compose exec service-a node -e "fetch('http://service-b:3002/health').then(r=>r.json()).then(d=>console.log(JSON.stringify(d,null,2)))"
docker compose exec service-b node -e "fetch('http://service-c:3003/health').then(r=>r.json()).then(d=>console.log(JSON.stringify(d,null,2)))"

# Trace one request
curl -fsS http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: demo-container-001"
docker compose logs | grep demo-container-001
```

See [docs/CONTAINER_VALIDATION.md](CONTAINER_VALIDATION.md) for the full validation checklist.

## 6. Daily commands

```bash
docker compose ps                          # status
docker compose logs -f                     # all logs
docker compose logs -f service-a           # one service
docker compose stop service-b              # stop one service
docker compose start service-b             # start it again
docker compose down                        # shut everything down
make test                           # re-run validation
```

## 7. Stop Service B failure test

```bash
docker compose stop service-b
code=$(curl -sS -o /tmp/service-b-down.json -w "%{http_code}" http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: fail-service-b-001" || true)
cat /tmp/service-b-down.json; echo
[ "$code" -ge 500 ] && echo "OK: request failed while B is down (HTTP $code)" || echo "UNEXPECTED: request returned HTTP $code"
docker compose logs service-a | grep fail-service-b-001

docker compose start service-b
curl -fsS http://localhost:8080/service-a/greet-service-b
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Cannot connect to the Docker daemon` | Docker Desktop not running | `open -a Docker` and wait for it to start |
| `port 8080 already in use` | Another process on 8080 | Change the host port in `docker-compose.yml` (e.g. `"8081:8080"`) |
| `service-a` keeps restarting | B or C not healthy yet | `docker compose logs service-a`; wait and retry |
| Nginx 502 | Stale upstream IP (nginx DNS cache) or service-a not ready | `docker compose ps`; `docker compose logs nginx` (look for `Connection refused`); `docker compose restart nginx` after config update |
| `curl localhost:8080` fails | Containers not up | `docker compose up --build -d` |
