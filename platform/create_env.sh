#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:-}"
TTL_MINUTES="${2:-30}"

if [ -z "$ENV_NAME" ]; then
    echo "Usage: $0 <name> [ttl_minutes]"
    exit 1
fi

ENV_ID="env-${ENV_NAME}-$(openssl rand -hex 3)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$PROJECT_ROOT/envs"
NGINX_CONF_DIR="$PROJECT_ROOT/nginx/conf.d"
LOGS_DIR="$PROJECT_ROOT/logs/$ENV_ID"
CREATED_AT=$(date -u +%s)
TTL_SECONDS=$((TTL_MINUTES * 60))
EXPIRES_AT=$((CREATED_AT + TTL_SECONDS))

find_free_port() {
    python3 -c "
import socket, random, sys
for _ in range(100):
    port = random.randint(10000, 19999)
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(1)
    result = sock.connect_ex(('localhost', port))
    sock.close()
    if result != 0:
        print(port)
        sys.exit(0)
print('ERROR: No free ports', file=sys.stderr)
sys.exit(1)
"
}

APP_PORT=$(find_free_port)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Creating sandbox environment"
echo "  ID:      $ENV_ID"
echo "  Name:    $ENV_NAME"
echo "  TTL:     ${TTL_MINUTES} minutes"
echo "  Port:    $APP_PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

mkdir -p "$LOGS_DIR"

echo "→ Creating Docker network: $ENV_ID"
docker network create "$ENV_ID" > /dev/null

echo "→ Starting app container..."
CONTAINER_ID=$(docker run -d \
    --name "${ENV_ID}-app" \
    --network "$ENV_ID" \
    --label "sandbox.env=$ENV_ID" \
    --label "sandbox.name=$ENV_NAME" \
    -e "ENV_ID=$ENV_ID" \
    -e "ENV_NAME=$ENV_NAME" \
    sandbox-app:latest)

echo "→ Connecting to platform network..."
if docker network connect platform-network "${ENV_ID}-app"; then
    echo "  ✓ Connected to platform network"
else
    echo "  ✗ Failed to connect to platform network"
    docker rm -f "${ENV_ID}-app" 2>/dev/null || true
    docker network rm "$ENV_ID" 2>/dev/null || true
    exit 1
fi

echo "  ✓ Container started: ${CONTAINER_ID:0:12}"

echo "→ Starting log shipping..."
docker logs -f "$CONTAINER_ID" >> "$LOGS_DIR/app.log" 2>&1 &
LOG_PID=$!
echo $LOG_PID > "$LOGS_DIR/log_shipper.pid"
echo "  ✓ Log shipper PID: $LOG_PID"

echo "→ Writing Nginx config..."
NGINX_CONF="$NGINX_CONF_DIR/${ENV_ID}.conf"
printf '# Auto-generated for environment: %s\nlocation /env/%s/ {\n    resolver 127.0.0.11 valid=30s ipv6=off;\n    set $upstream %s-app:5000;\n    proxy_pass http://$upstream/;\n    proxy_set_header Host $host;\n    proxy_set_header X-Real-IP $remote_addr;\n}\nlocation /env/%s/health {\n    resolver 127.0.0.11 valid=30s ipv6=off;\n    set $upstream %s-app:5000;\n    proxy_pass http://$upstream/health;\n    proxy_set_header Host $host;\n}\n' \
    "$ENV_ID" "$ENV_ID" "$ENV_ID" "$ENV_ID" "$ENV_ID" \
    > "$NGINX_CONF"

echo "→ Reloading Nginx..."
docker exec platform-nginx nginx -s reload
echo "  ✓ Nginx reloaded"

echo "→ Writing state file..."
STATE_FILE="$ENVS_DIR/${ENV_ID}.json"
TEMP_FILE="$ENVS_DIR/.tmp_${ENV_ID}.json"
python3 -c "
import json
data = {
    'id': '$ENV_ID',
    'name': '$ENV_NAME',
    'created_at': $CREATED_AT,
    'ttl_seconds': $TTL_SECONDS,
    'expires_at': $EXPIRES_AT,
    'status': 'running',
    'app_port': $APP_PORT,
    'container_id': '$CONTAINER_ID',
    'log_shipper_pid': $LOG_PID
}
with open('$TEMP_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
mv "$TEMP_FILE" "$STATE_FILE"
echo "  ✓ State file written"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Environment ready"
echo "  URL:     http://localhost/env/$ENV_ID/"
echo "  Health:  http://localhost/env/$ENV_ID/health"
echo "  Logs:    make logs ENV=$ENV_ID"
echo "  TTL:     ${TTL_MINUTES} minutes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
