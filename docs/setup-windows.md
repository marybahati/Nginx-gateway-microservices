# Setup — Windows (Docker Compose)

Goal: run the full Nginx gateway microservices stack on Windows using Docker Compose. ~10 minutes from a clean machine.

**Docker must be installed and running locally.** This guide walks through installing Docker Desktop on Windows.

## 1. Host requirements

| Resource | Minimum |
|---|---|
| Docker | **Required** — [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/) (see below) |
| CPU | 2 cores (virtualization enabled in BIOS) |
| RAM | 4 GB free |
| Disk | 5 GB free for images |
| Windows | 10 (build 19041+) or 11 |

Confirm virtualization: Task Manager → Performance → CPU → "Virtualization: Enabled".

## 2. Install Docker Desktop

```powershell
winget install Docker.DockerDesktop
```

Restart if prompted, then open Docker Desktop and wait until it reports "Engine running".

```bash
docker --version
docker compose version
```

Use **Docker Desktop 4.x or newer** (includes Docker Compose V2). Avoid the legacy `docker-compose` v1-only install.

Download: [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/)

## 3. Clone the repository

Use PowerShell or Git Bash:

```powershell
New-Item -ItemType Directory -Force -Path $HOME\nginx-microservices
cd $HOME\nginx-microservices
git clone <your-repo-url> Nginx-gateway-microservices
cd Nginx-gateway-microservices
git checkout feat/docker
```

## 4. Start the system

```powershell
docker compose up --build -d
docker compose ps
```

Expected: four containers running — `nginx`, `service-a`, `service-b`, `service-c`.

## 5. Validate

From PowerShell or Git Bash:

```powershell
curl.exe -i http://localhost:8080/service-a/health
curl.exe -i http://localhost:8080/service-a/greet-service-b
```

Or use WSL / Git Bash with the Makefile (requires `make`):

```bash
make test
```

Without `make`, run the equivalent checks manually (see [docs/CONTAINER_VALIDATION.md](CONTAINER_VALIDATION.md)).

Manual checks:

```powershell
# B and C are NOT reachable from the host
curl.exe -i --connect-timeout 3 http://localhost:3002/health
curl.exe -i --connect-timeout 3 http://localhost:3003/health

# Internal discovery
docker compose exec service-a curl -i http://service-b:3002/health
docker compose exec service-b curl -i http://service-c:3003/health

# Trace one request
curl.exe -i http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: demo-container-001"
docker compose logs | findstr demo-container-001
```

See [docs/CONTAINER_VALIDATION.md](CONTAINER_VALIDATION.md) for the full validation checklist.

## 6. Daily commands

```powershell
docker compose ps
docker compose logs -f
docker compose logs -f service-a
docker compose stop service-b
docker compose start service-b
docker compose down
```

## 7. Stop Service B failure test

```powershell
docker compose stop service-b
curl.exe -i http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: fail-service-b-001"
docker compose logs service-a

docker compose start service-b
curl.exe -i http://localhost:8080/service-a/greet-service-b
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Docker Desktop is unable to start` | WSL2 or Hyper-V not enabled | Enable WSL2: `wsl --install`; restart |
| `port 8080 already in use` | Another process on 8080 | Change host port in `docker-compose.yml` |
| `service-a` keeps restarting | B or C not healthy | `docker compose logs service-a` |
| Nginx 502 | Service A not ready | `docker compose ps` |
