#!/usr/bin/env bash
# destroy_env.sh — Destroys a sandbox environment completely
# Usage: ./destroy_env.sh <env_id>

set -euo pipefail

ENV_ID="${1:-}"
if [ -z "$ENV_ID" ]; then
    echo "Usage: $0 <env_id>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$PROJECT_ROOT/envs"
NGINX_CONF_DIR="$PROJECT_ROOT/nginx/conf.d"
LOGS_DIR="$PROJECT_ROOT/logs/$ENV_ID"
ARCHIVE_DIR="$PROJECT_ROOT/logs/archived/$ENV_ID"
STATE_FILE="$ENVS_DIR/${ENV_ID}.json"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Destroying environment: $ENV_ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Kill log shipper ──────────────────────────────────────────────────────────
# Must kill before stopping container or it becomes a zombie process
PID_FILE="$LOGS_DIR/log_shipper.pid"
if [ -f "$PID_FILE" ]; then
    LOG_PID=$(cat "$PID_FILE")
    echo "→ Stopping log shipper (PID: $LOG_PID)..."
    kill "$LOG_PID" 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "  ✓ Log shipper stopped"
fi

# ── Stop and remove all containers with this env's label ─────────────────────
echo "→ Removing containers..."
CONTAINERS=$(docker ps -aq --filter "label=sandbox.env=$ENV_ID" 2>/dev/null || true)
if [ -n "$CONTAINERS" ]; then
    docker stop $CONTAINERS 2>/dev/null || true
    docker rm $CONTAINERS 2>/dev/null || true
    echo "  ✓ Containers removed"
else
    echo "  (no containers found)"
fi

# ── Remove Docker network ─────────────────────────────────────────────────────
echo "→ Removing Docker network: $ENV_ID"
docker network rm "$ENV_ID" 2>/dev/null || true
echo "  ✓ Network removed"

# ── Remove Nginx config and reload ───────────────────────────────────────────
NGINX_CONF="$NGINX_CONF_DIR/${ENV_ID}.conf"
if [ -f "$NGINX_CONF" ]; then
    echo "→ Removing Nginx config..."
    rm -f "$NGINX_CONF"
    docker exec platform-nginx nginx -s reload 2>/dev/null || true
    echo "  ✓ Nginx config removed and reloaded"
fi

# ── Archive logs ──────────────────────────────────────────────────────────────
if [ -d "$LOGS_DIR" ]; then
    echo "→ Archiving logs..."
    mkdir -p "$ARCHIVE_DIR"
    cp -r "$LOGS_DIR/." "$ARCHIVE_DIR/" 2>/dev/null || true
    # Add destruction timestamp to archive
    echo "Destroyed at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" \
        >> "$ARCHIVE_DIR/destroy.log"
    rm -rf "$LOGS_DIR"
    echo "  ✓ Logs archived to logs/archived/$ENV_ID/"
fi

# ── Delete state file ─────────────────────────────────────────────────────────
if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
    echo "  ✓ State file deleted"
fi

echo ""
echo "✓ Environment $ENV_ID destroyed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
