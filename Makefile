# nginx-gateway-microservices — Makefile

SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE := docker compose

.PHONY: help up down ps logs restart stop-service start-service test lint \
        docker-up docker-down docker-ps docker-logs docker-test docker-restart docker-stop-service docker-start-service

help:  ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

up:  ## Build and start all containers.
	$(COMPOSE) up --build -d

down:  ## Stop and remove containers and network.
	$(COMPOSE) down

ps:  ## Show container status.
	$(COMPOSE) ps

logs:  ## Follow logs for all services.
	$(COMPOSE) logs -f

restart:  ## Restart all application containers and nginx.
	$(COMPOSE) restart service-b service-c service-a nginx

stop-service:  ## Stop one service (usage: make stop-service SVC=service-b).
	$(COMPOSE) stop $(SVC)

start-service:  ## Start one service (usage: make start-service SVC=service-b).
	$(COMPOSE) start $(SVC)

test:  ## Run all Docker validation checks (full 7-test suite).
	@echo "=== [1/7] Containers running ==="
	@count=$$($(COMPOSE) ps --status running -q | wc -l | tr -d ' '); \
	if [ "$$count" -eq 4 ]; then echo "OK: all four services running"; else echo "FAIL: expected 4 running containers, got $$count"; $(COMPOSE) ps; exit 1; fi
	@echo ""
	@echo "=== [2/7] Service A via Nginx (:8080) ==="
	@curl -sf http://localhost:8080/service-a/health | python3 -m json.tool
	@echo ""
	@echo "=== [3/7] Service B not exposed from host ==="
	@curl -sf --connect-timeout 3 http://localhost:3002/health && echo "UNEXPECTED: B is exposed" && exit 1 || echo "OK: connection refused or timed out"
	@echo ""
	@echo "=== [4/7] Service C not exposed from host ==="
	@curl -sf --connect-timeout 3 http://localhost:3003/health && echo "UNEXPECTED: C is exposed" && exit 1 || echo "OK: connection refused or timed out"
	@echo ""
	@echo "=== [5/7] Internal discovery ==="
	@$(COMPOSE) exec -T service-a curl -sf http://service-b:3002/health | python3 -m json.tool
	@$(COMPOSE) exec -T service-b curl -sf http://service-c:3003/health | python3 -m json.tool
	@echo ""
	@echo "=== [6/7] Request tracing ==="
	@curl -sf http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: make-docker-test-trace" | python3 -m json.tool
	@$(COMPOSE) logs 2>&1 | grep -q make-docker-test-trace && echo "OK: request ID found in logs" || (echo "FAIL: request ID not found in logs" && exit 1)
	@echo ""
	@echo "=== [7/7] Stop Service B, observe failure, recover ==="
	@$(COMPOSE) stop service-b
	@curl -sf http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: make-fail-service-b" >/dev/null && echo "UNEXPECTED: request succeeded while B is down" && $(COMPOSE) start service-b && exit 1 || echo "OK: request failed while B is down"
	@$(COMPOSE) logs service-a 2>&1 | grep -q make-fail-service-b && echo "OK: failure logged by service-a" || (echo "FAIL: failure not logged" && $(COMPOSE) start service-b && exit 1)
	@$(COMPOSE) start service-b
	@sleep 2
	@curl -sf http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: make-recover-001" | python3 -m json.tool
	@echo ""
	@echo "All Docker validation commands succeeded."

docker-up: up  ## Alias for make up.
docker-down: down  ## Alias for make down.
docker-ps: ps  ## Alias for make ps.
docker-logs: logs  ## Alias for make logs.
docker-restart: restart  ## Alias for make restart.
docker-stop-service: stop-service  ## Alias for make stop-service.
docker-start-service: start-service  ## Alias for make start-service.
docker-test: test  ## Alias for make test.

lint:  ## Syntax-check shell scripts.
	@set -e; for f in scripts/*.sh; do \
	  echo "  bash -n $$f"; bash -n "$$f"; \
	done; echo "  ok"
