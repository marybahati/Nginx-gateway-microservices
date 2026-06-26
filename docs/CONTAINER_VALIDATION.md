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

<img width="723" height="543" alt="image" src="https://github.com/user-attachments/assets/281a52ad-1960-4627-a588-90bd2d9a4e88" />

---

## 2. Confirm containers are running

```bash
docker compose ps
```

<img width="828" height="332" alt="image" src="https://github.com/user-attachments/assets/a97ce472-f2eb-473e-ade0-2f25fa7bb057" />


All four services are running. Only Nginx publishes a host port (`8080:80`).

---

## 3. Test public entry point

```bash
curl -i http://localhost:8080/service-a/health
```

<img width="827" height="296" alt="image" src="https://github.com/user-attachments/assets/74de8e60-9585-4b85-b8a1-bf71964ae17c" />


Full flow:

```bash
curl -i http://localhost:8080/service-a/greet-service-b
```

<img width="829" height="221" alt="image" src="https://github.com/user-attachments/assets/b53599bf-d4ac-4dd3-ac3b-b99b9fbf8b72" />


---

## 4. Prove B and C are not directly exposed

From the host:

```bash
curl -i --connect-timeout 3 http://localhost:3002/health
curl -i --connect-timeout 3 http://localhost:3003/health
```

<img width="850" height="204" alt="image" src="https://github.com/user-attachments/assets/720c239d-6743-484a-97e8-c3f9f21a4de4" />


Connection refused — ports 3002 and 3003 are not published to the host.

Nginx also returns 404 for direct B/C routes:

```bash
curl -i http://localhost:8080/service-b/health   # 404
curl -i http://localhost:8080/service-c/health   # 404
```
<img width="850" height="685" alt="image" src="https://github.com/user-attachments/assets/607e1b47-d92b-4cd9-8f53-37858e07fe89" />

---

## 5. Prove internal service discovery works

From inside the Docker Compose network:

```bash
docker compose exec service-a node -e "fetch('http://service-b:3002/health').then(r=>r.json()).then(console.log)"
docker compose exec service-b node -e "fetch('http://service-c:3003/health').then(r=>r.json()).then(console.log)"
```

<img width="850" height="424" alt="image" src="https://github.com/user-attachments/assets/9265a2f8-4c09-45bb-9d5d-8058d5d5d1eb" />


Services communicate using Compose DNS names (`service-b`, `service-c`), not `localhost`.

---

## 6. Trace one request

```bash
curl -i http://localhost:8080/service-a/greet-service-b \
  -H "X-Request-ID: demo-container-001"

docker compose logs | grep demo-container-001
```

Log grep output (same request ID in all four services):

<img width="1053" height="740" alt="image" src="https://github.com/user-attachments/assets/9ded9488-7793-44c8-a0d9-470a41a5a4fc" />

---

## 7. Stop Service B and observe failure

```bash
docker compose stop service-b

curl -i http://localhost:8080/service-a/greet-service-b \
  -H "X-Request-ID: fail-service-b-001"
```


Service A logs the failure:

```bash
docker compose logs service-a | grep fail-service-b-001
```

<img width="1039" height="524" alt="image" src="https://github.com/user-attachments/assets/feba4c0b-bd7d-4f51-a9a5-bebbb29d391e" />


**Recover:**

```bash
docker compose start service-b

curl -i http://localhost:8080/service-a/greet-service-b \
  -H "X-Request-ID: recover-001"
```

<img width="1056" height="400" alt="image" src="https://github.com/user-attachments/assets/c913d5cd-e3b2-4341-a9cf-9a68e4161eed" />


Unlike a systemd `Requires=` coupling, stopping Service B in Docker does **not** stop Service A. Service A stays running and returns a clear **500** error until B is restarted.

**If you see 502 instead of 500** after stopping/starting containers, Nginx may be using a stale `service-a` IP (classic Docker + Nginx DNS caching). Check `docker compose logs nginx` for `connect() failed (111: Connection refused)`. The repo config uses `resolver 127.0.0.11` and `server … resolve` in `nginx/nginx-docker.conf` so Nginx re-resolves `service-a` every ~10s. After updating that file, run `docker compose restart nginx` once, then confirm all services are up with `docker compose ps`.

---

## Quick validation

Run all 7 checks in one command:

```bash
make test
```


All Docker validation commands succeeded.

<img width="1346" height="876" alt="image" src="https://github.com/user-attachments/assets/9d24dae3-a4e5-4a78-9104-1bbd3b16cb2f" />
