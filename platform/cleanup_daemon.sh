#!/usr/bin/env bash
# cleanup_daemon.sh — Auto-destroys expired environments
# Runs in the background, checks every 60 seconds
# Start with: nohup ./platform/cleanup_daemon.sh &

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$PROJECT_ROOT/envs"
LOG_FILE="$PROJECT_ROOT/logs/cleanup.log"

mkdir -p "$PROJECT_ROOT/logs"

log() {
    # Every log line gets a timestamp
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" | tee -a "$LOG_FILE"
}

log "Cleanup daemon started (PID: $$)"

while true; do
    NOW=$(date -u +%s)

    # Check every state file in envs/
    for STATE_FILE in "$ENVS_DIR"/*.json; do
        # Skip if no files exist (glob returns literal string)
        [ -f "$STATE_FILE" ] || continue

        # Parse expires_at from state file
        # Using Python for reliable JSON parsing
        EXPIRES_AT=$(python3 -c "
import json, sys
with open('$STATE_FILE') as f:
    d = json.load(f)
print(d.get('expires_at', 0))
" 2>/dev/null || echo "0")

        ENV_ID=$(python3 -c "
import json
with open('$STATE_FILE') as f:
    d = json.load(f)
print(d.get('id', ''))
" 2>/dev/null || echo "")

        if [ -z "$ENV_ID" ]; then
            continue
        fi

        # Check if expired
        if [ "$NOW" -gt "$EXPIRES_AT" ]; then
            log "Environment $ENV_ID has expired — destroying"
            "$SCRIPT_DIR/destroy_env.sh" "$ENV_ID" >> "$LOG_FILE" 2>&1
            log "Environment $ENV_ID destroyed successfully"
        else
            REMAINING=$((EXPIRES_AT - NOW))
            log "Environment $ENV_ID — ${REMAINING}s remaining"
        fi
    done

    # Sleep 60 seconds before next check
    sleep 60
done
