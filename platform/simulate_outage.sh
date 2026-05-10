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
        echo "→ Attempting recovery..."
        CONTAINER="${ENV_ID}-app"

        # Get current state
        STATUS=$(docker inspect --format='{{.State.Status}}' \
            "$CONTAINER" 2>/dev/null || echo "missing")
        echo "  Current status: $STATUS"

        if [ "$STATUS" = "missing" ]; then
            # Container was killed — need to recreate it
            STATE_FILE="$(dirname "$SCRIPT_DIR")/envs/${ENV_ID}.json"
            ENV_NAME=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['name'])")
            docker run -d \
                --name "$CONTAINER" \
                --network "$ENV_ID" \
                --label "sandbox.env=$ENV_ID" \
                --label "sandbox.name=$ENV_NAME" \
                -e "ENV_ID=$ENV_ID" \
                -e "ENV_NAME=$ENV_NAME" \
                sandbox-app:latest
            docker network connect platform-network "$CONTAINER"
            echo "  ✓ Container recreated"
        elif [ "$STATUS" = "paused" ]; then
            docker unpause "$CONTAINER"
            echo "  ✓ Container unpaused"
        elif [ "$STATUS" = "exited" ]; then
            docker start "$CONTAINER"
            echo "  ✓ Container restarted"
        fi

        # Reconnect to platform network if disconnected
        docker network connect platform-network "$CONTAINER" 2>/dev/null && \
            echo "  ✓ Network reconnected" || true

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
