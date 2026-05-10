.PHONY: up down create destroy logs health simulate clean build

# Start the platform
up:
	docker compose up -d
	@echo "Starting cleanup daemon..."
	@nohup ./platform/cleanup_daemon.sh > logs/daemon.log 2>&1 &
	@echo "✓ Platform running at http://localhost"
	@echo "✓ API available at http://localhost:8000"

# Stop everything
down:
	@echo "Destroying all environments..."
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		ENV_ID=$$(python3 -c "import json; print(json.load(open('$$f'))['id'])"); \
		./platform/destroy_env.sh $$ENV_ID; \
	done
	docker compose down
	@pkill -f cleanup_daemon.sh 2>/dev/null || true
	@pkill -f health_poller.py 2>/dev/null || true

# Create a new environment
create:
	@read -p "Environment name: " name; \
	read -p "TTL in minutes [30]: " ttl; \
	ttl=$${ttl:-30}; \
	./platform/create_env.sh $$name $$ttl

# Destroy a specific environment
destroy:
	@[ -n "$(ENV)" ] || (echo "Usage: make destroy ENV=<env_id>" && exit 1)
	./platform/destroy_env.sh $(ENV)

# Tail environment logs
logs:
	@[ -n "$(ENV)" ] || (echo "Usage: make logs ENV=<env_id>" && exit 1)
	@tail -f logs/$(ENV)/app.log

# Show all environment health statuses
health:
	@echo "Environment Health Status"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		python3 -c " \
import json, time; \
d = json.load(open('$$f')); \
remaining = max(0, d['expires_at'] - int(time.time())); \
print(f\"  {d['id']}: status={d['status']} ttl={remaining}s remaining\")"; \
	done || echo "  No active environments"

# Run outage simulation
simulate:
	@[ -n "$(ENV)" ] || (echo "Usage: make simulate ENV=<env_id> MODE=<mode>" && exit 1)
	@[ -n "$(MODE)" ] || (echo "Usage: make simulate ENV=<env_id> MODE=<mode>" && exit 1)
	./platform/simulate_outage.sh --env $(ENV) --mode $(MODE)

# Build all images
build:
	docker build -t sandbox-app:latest ./platform/demo-app

# Wipe all state, logs, archives
clean:
	@echo "Wiping all state and logs..."
	@rm -rf envs/*.json logs/*/
	@rm -f nginx/conf.d/env-*.conf
	@echo "✓ Clean complete"
