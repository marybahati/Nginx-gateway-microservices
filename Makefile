# nginx-gateway-microservices — Makefile

SHELL := /bin/bash
.DEFAULT_GOAL := help

SERVICES := service-a service-b service-c

.PHONY: help install uninstall health start stop restart status logs test lint

help:  ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install:  ## Run install.sh (requires sudo).
	sudo ./install.sh

uninstall:  ## Remove all services and /opt install (requires sudo).
	sudo ./uninstall.sh

health:  ## Print system + service snapshot.
	./healthcheck.sh

start:  ## Start all microservices and nginx.
	sudo systemctl start $(SERVICES) nginx

stop:  ## Stop nginx and all microservices.
	sudo systemctl stop nginx $(SERVICES)

restart:  ## Restart all microservices and reload nginx.
	sudo systemctl restart $(SERVICES)
	sudo nginx -t && sudo systemctl reload nginx

status:  ## Show systemctl status for nginx and all microservices.
	systemctl --no-pager status nginx $(SERVICES) || true

logs:  ## Tail journald logs for all microservices.
	journalctl -f $(addprefix -u ,$(SERVICES))

nginx-logs:  ## Tail structured Nginx gateway access log.
	sudo tail -f /var/log/nginx/nginx-gateway-access.log

test:  ## Run all validation commands from the API contract.
	@echo "=== Service A (via Nginx) ==="
	@curl -sf http://localhost/service-a/health | python3 -m json.tool
	@echo ""
	@echo "=== Service B (internal) ==="
	@curl -sf http://service-b.internal:3002/health | python3 -m json.tool
	@echo ""
	@echo "=== Service C (internal) ==="
	@curl -sf http://service-c.internal:3003/health | python3 -m json.tool
	@echo ""
	@curl -sf http://localhost/service-a/greet-service-b | python3 -m json.tool
	@echo ""
	@echo "All validation commands succeeded."

lint:  ## Syntax-check shell scripts.
	@set -e; for f in install.sh uninstall.sh healthcheck.sh; do \
	  echo "  bash -n $$f"; bash -n "$$f"; \
	done; echo "  ok"
