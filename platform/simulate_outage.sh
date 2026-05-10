#!/usr/bin/env bash
# simulate_outage.sh — Simulates various failure modes
# Usage: ./simulate_outage.sh --env <env_id> --mode <mode>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

ENV_ID=""
MODE=""

# Parse flags
while [[ $# -gt 0 ]]; do
    case $1 in
        --env) ENV_ID="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

if [ -z "$ENV_ID" ] || [ -z "$MODE" ]; then
    echo "Usage: $0 --env <env_id> --mode <crash|pause|network|recover>"
    exit 1
fi

# ── Safety guard ──────────────────────────────────────────────────────────────
# Never simulate against platform infrastructure containers
PROTECTED_NAMES=("platform-nginx" "platform-api" "platform-daemon")
if [[ " ${PROTECTED_NAMES[*]} " =~ " $ENV_ID " ]]; then
    echo "ERROR: Cannot simulate outage against protected container: $ENV_ID"
    exit 1
fi

# Also check the container name doesn't match protected patterns
CONTAINER="${ENV_ID}-app"
CONTAINER_NAME=$(docker inspect --format='{{.Name}}' "$CONTAINER" 2>/dev/null || echo "")
for protected in "${PROTECTED_NAMES[@]}"; do
    if [[ "$CONTAINER_NAME" == *"$protected"* ]]; then
        echo "ERROR: Refusing to simulate against protected container"
        exit 1
    fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Simulating outage"
echo "  Environment: $ENV_ID"
echo "  Mode:        $MODE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

case "$MODE" in
    crash)
        # Hard kill — container stops immediately
        # Health monitor should detect within 90s (3 failed checks * 30s)
        echo "→ Crashing container: $CONTAINER"
        docker kill "$CONTAINER"
        echo "  ✓ Container killed — health monitor will detect within 90s"
        ;;

    pause)
        # Freeze the container — it still exists but stops responding
        echo "→ Pausing container: $CONTAINER"
        docker pause "$CONTAINER"
        echo "  ✓ Container paused — use --mode recover to unpause"
        ;;

    network)
        # Disconnect from platform network — Nginx can't reach it
        echo "→ Disconnecting container from platform network..."
        docker network disconnect platform-network "$CONTAINER"
        echo "  ✓ Network disconnected — use --mode recover to reconnect"
        ;;

    recover)
        # Restore whatever was broken
        echo "→ Attempting recovery..."

        # Try to unpause if paused
        docker unpause "$CONTAINER" 2>/dev/null && \
            echo "  ✓ Container unpaused" || true

        # Try to reconnect to platform network if disconnected
        docker network connect platform-network "$CONTAINER" 2>/dev/null && \
            echo "  ✓ Reconnected to platform network" || true

        # Restart if crashed (not running)
        STATUS=$(docker inspect --format='{{.State.Status}}' \
            "$CONTAINER" 2>/dev/null || echo "missing")
        if [ "$STATUS" != "running" ]; then
            docker start "$CONTAINER" 2>/dev/null && \
                echo "  ✓ Container restarted" || \
                echo "  ✗ Could not restart — may need manual intervention"
        fi

        echo "  ✓ Recovery complete"
        ;;

    stress)
        # Optional — spike CPU with stress-ng if available
        echo "→ Running CPU stress test for 30 seconds..."
        docker exec "$CONTAINER" sh -c \
            "apk add --no-cache stress-ng 2>/dev/null; \
             stress-ng --cpu 2 --timeout 30s" &
        echo "  ✓ Stress test started (30s)"
        ;;

    *)
        echo "ERROR: Unknown mode '$MODE'"
        echo "Valid modes: crash, pause, network, recover, stress"
        exit 1
        ;;
esac

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
