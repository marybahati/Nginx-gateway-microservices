# Setup — Linux (Docker Compose)

Goal: run the full Nginx gateway microservices stack on your Linux machine using Docker Compose. ~5 minutes from a clean machine.

**Docker must be installed and running locally.** This guide walks through installing Docker Engine and the Compose plugin on Linux.

## 1. Host requirements

| Resource | Minimum |
|---|---|
| Docker | **Required** — Docker Engine + Compose plugin (see below) |
| CPU | 2 cores |
| RAM | 4 GB free |
| Disk | 5 GB free for images |
| Distro | Any modern Linux — Ubuntu, Fedora, Arch, Debian, etc. |

## 2. Install Docker Engine + Compose

**Ubuntu / Debian:**

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2
sudo usermod -aG docker $USER
newgrp docker
docker --version
docker compose version
```

**Fedora:**

```bash
sudo dnf install -y docker docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

Official install guide (all distros): https://docs.docker.com/engine/install/

## 3. Clone the repository

```bash
mkdir -p ~/nginx-microservices
cd ~/nginx-microservices
git clone <your-repo-url> Nginx-gateway-microservices
cd Nginx-gateway-microservices
git checkout feat/docker    # or your Docker branch
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
curl -i http://localhost:8080/service-a/health
curl -i http://localhost:8080/service-a/greet-service-b

# B and C are NOT reachable from the host
curl -i --connect-timeout 3 http://localhost:3002/health
curl -i --connect-timeout 3 http://localhost:3003/health

# Internal discovery
docker compose exec service-a curl -i http://service-b:3002/health
docker compose exec service-b curl -i http://service-c:3003/health

# Trace one request
curl -i http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: demo-container-001"
docker compose logs | grep demo-container-001
```

See [docs/CONTAINER_VALIDATION.md](CONTAINER_VALIDATION.md) for the full validation checklist.

## 6. Daily commands

```bash
docker compose ps
docker compose logs -f
docker compose logs -f service-a
docker compose stop service-b
docker compose start service-b
docker compose down
make test
```

## 7. Stop Service B failure test

```bash
docker compose stop service-b
curl -i http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: fail-service-b-001"
docker compose logs service-a | grep fail-service-b-001

docker compose start service-b
curl -i http://localhost:8080/service-a/greet-service-b
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `permission denied` on docker | User not in `docker` group | `sudo usermod -aG docker $USER && newgrp docker` |
| `port 8080 already in use` | Another process on 8080 | Change host port in `docker-compose.yml` |
| `service-a` keeps restarting | Dependency wait failed | `docker compose logs service-a service-b service-c` |
| Nginx 502 | Service A not ready | `docker compose ps`; check logs |
