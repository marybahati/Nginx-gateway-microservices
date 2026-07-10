# nginx-gateway-microservices — Makefile

SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE := docker compose

.PHONY: help up down ps logs restart stop-service start-service test melt-test lint \
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

test:  ## Run application validation checks (7 tests).
	@echo "=== [1/7] Application containers running ==="
	@for svc in service-a service-b service-c nginx; do \
	  if [ -z "$$($(COMPOSE) ps --status running -q $$svc)" ]; then \
	    echo "FAIL: $$svc is not running"; $(COMPOSE) ps; exit 1; \
	  fi; \
	done; echo "OK: service-a, service-b, service-c, nginx are running"
	@echo ""
	@echo "=== [2/7] Service A via Nginx (:8080) ==="
	@curl -sf http://localhost:8080/service-a/health; echo
	@echo ""
	@echo "=== [3/7] Service B not exposed from host ==="
	@curl -sf --connect-timeout 3 http://localhost:3002/health && echo "UNEXPECTED: B is exposed" && exit 1 || echo "OK: connection refused or timed out"
	@echo ""
	@echo "=== [4/7] Service C not exposed from host ==="
	@curl -sf --connect-timeout 3 http://localhost:3003/health && echo "UNEXPECTED: C is exposed" && exit 1 || echo "OK: connection refused or timed out"
	@echo ""
	@echo "=== [5/7] Internal discovery ==="
	@$(COMPOSE) exec -T service-a node -e "fetch('http://service-b:3002/health').then(r=>r.json()).then(d=>console.log(JSON.stringify(d,null,2)))"
	@$(COMPOSE) exec -T service-b node -e "fetch('http://service-c:3003/health').then(r=>r.json()).then(d=>console.log(JSON.stringify(d,null,2)))"
	@echo ""
	@echo "=== [6/7] Request tracing ==="
	@trace_id="make-trace-$$(date +%s)"; \
	curl -sf http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: $$trace_id"; echo; \
	$(COMPOSE) logs --since 2m 2>&1 | grep -q "$$trace_id" && echo "OK: request ID found in logs ($$trace_id)" || (echo "FAIL: request ID not found in logs ($$trace_id)" && exit 1)
	@echo ""
	@echo "=== [7/7] Stop Service B, observe failure, recover ==="
ifeq ($(SKIP_STOP_TEST),1)
	@echo "SKIP: stop/recover test (SKIP_STOP_TEST=1). Run step 7 manually — see docs/setup-linux.md"
else
	@$(COMPOSE) stop service-b || { \
	  echo ""; \
	  echo "FAIL: docker compose stop service-b failed (often 'permission denied' on Linux)."; \
	  echo "  • Use the same user for 'docker compose up' and 'make test' (avoid sudo on only one)."; \
	  echo "  • Snap Docker: replace with official Docker Engine — docs/setup-linux.md#replace-snap-docker-with-official-docker-engine"; \
	  echo "  • To skip this step: make test SKIP_STOP_TEST=1"; \
	  exit 1; \
	}
	@fail_id="make-fail-$$(date +%s)"; \
	code=$$(curl -sS -o /tmp/nginx-gateway-fail-response.json -w "%{http_code}" http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: $$fail_id" || true); \
	cat /tmp/nginx-gateway-fail-response.json; echo; \
	if [ "$$code" -ge 500 ]; then echo "OK: request failed while B is down (HTTP $$code)"; else echo "UNEXPECTED: request returned HTTP $$code"; $(COMPOSE) start service-b; exit 1; fi; \
	$(COMPOSE) logs --since 2m service-a 2>&1 | grep -q "$$fail_id" && echo "OK: failure logged by service-a ($$fail_id)" || (echo "FAIL: failure not logged ($$fail_id)" && $(COMPOSE) start service-b && exit 1)
	@$(COMPOSE) start service-b
	@sleep 2
	@recover_id="make-recover-$$(date +%s)"; \
	curl -sf http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: $$recover_id"; echo
endif
	@echo ""
	@echo "All Docker validation commands succeeded."

melt-test:  ## Run observability validation (Prometheus, Grafana, Jaeger, metrics, traces).
	@echo "=== [1/6] Observability containers running ==="
	@for svc in prometheus grafana jaeger loki promtail; do \
	  if [ -z "$$($(COMPOSE) ps --status running -q $$svc)" ]; then \
	    echo "FAIL: $$svc is not running"; $(COMPOSE) ps; exit 1; \
	  fi; \
	done; echo "OK: prometheus, grafana, jaeger, loki, promtail are running"
	@echo ""
	@echo "=== [2/6] Prometheus targets healthy ==="
	@curl -sf http://localhost:9090/-/ready >/dev/null
	@curl -sf http://localhost:9090/api/v1/targets | grep -q '"health":"up"' && echo "OK: at least one Prometheus target is up" || (echo "FAIL: no healthy Prometheus targets" && exit 1)
	@echo ""
	@echo "=== [3/6] Grafana ready ==="
	@curl -sf http://localhost:3030/api/health | grep -q '"database": "ok"' && echo "OK: Grafana is healthy" || (echo "FAIL: Grafana health check failed" && exit 1)
	@echo ""
	@echo "=== [4/6] Jaeger ready ==="
	@curl -sf http://localhost:16686 >/dev/null && echo "OK: Jaeger UI reachable"
	@echo ""
	@echo "=== [5/6] Service metrics endpoints ==="
	@$(COMPOSE) exec -T service-a node -e "fetch('http://127.0.0.1:3001/metrics').then(r=>r.text()).then(t=>process.exit(t.includes('http_requests_total')?0:1)).catch(()=>process.exit(1))" && echo "OK: service-a /metrics"
	@$(COMPOSE) exec -T service-b node -e "fetch('http://127.0.0.1:3002/metrics').then(r=>r.text()).then(t=>process.exit(t.includes('http_requests_total')?0:1)).catch(()=>process.exit(1))" && echo "OK: service-b /metrics"
	@$(COMPOSE) exec -T service-c node -e "fetch('http://127.0.0.1:3003/metrics').then(r=>r.text()).then(t=>process.exit(t.includes('http_requests_total')?0:1)).catch(()=>process.exit(1))" && echo "OK: service-c /metrics"
	@echo ""
	@echo "=== [6/6] Trace-producing request ==="
	@trace_id="melt-trace-$$(date +%s)"; \
	curl -sS --max-time 30 http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: $$trace_id"; echo; \
	$(COMPOSE) logs --since 2m service-a 2>&1 | grep -q "$$trace_id" && echo "OK: correlated logs found ($$trace_id)" || (echo "FAIL: trace request not found in logs" && exit 1)
	@echo ""
	@echo "All observability validation commands succeeded."

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
	done; echo "  node --check scripts/wait-for-deps.mjs"; node --check scripts/wait-for-deps.mjs; echo "  ok"
