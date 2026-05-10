#!/usr/bin/env python3
# health_poller.py — Polls /health endpoint of every active environment
# Runs continuously, checks every 30 seconds
# After 3 consecutive failures, marks environment as degraded

import os
import json
import time
import requests
import sys
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
ENVS_DIR = PROJECT_ROOT / "envs"
LOGS_DIR = PROJECT_ROOT / "logs"

# Track consecutive failures per environment
failure_counts = {}

def log(env_id: str, status_code: int, latency_ms: float, error: str = ""):
    """Writes one health check result to the env's health.log"""
    LOGS_DIR.mkdir(exist_ok=True)
    env_log_dir = LOGS_DIR / env_id
    env_log_dir.mkdir(exist_ok=True)

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    line = f"{timestamp} | status={status_code} | latency={latency_ms:.0f}ms"
    if error:
        line += f" | error={error}"

    log_file = env_log_dir / "health.log"
    with open(log_file, "a") as f:
        f.write(line + "\n")

    print(line)


def update_status(state_file: Path, status: str):
    """Updates the status field in an environment's state file"""
    try:
        with open(state_file) as f:
            state = json.load(f)
        state["status"] = status
        # Write atomically
        tmp = state_file.with_suffix(".tmp")
        with open(tmp, "w") as f:
            json.dump(state, f, indent=2)
        tmp.rename(state_file)
    except Exception as e:
        print(f"  Warning: Could not update state file: {e}")


def poll_environment(state_file: Path):
    try:
        with open(state_file) as f:
            state = json.load(f)
    except Exception:
        return

    env_id = state.get("id", "")
    container_name = f"{env_id}-app"

    # Hit the container directly via Docker exec
    # This bypasses Nginx and tests the app itself
    import subprocess
    result = subprocess.run(
        ["docker", "exec", container_name,
         "python3", "-c",
         "import urllib.request; r = urllib.request.urlopen('http://localhost:5000/health', timeout=5); print(r.status)"],
        capture_output=True, text=True, timeout=10
    )

    start = time.time()
    if result.returncode == 0 and "200" in result.stdout:
        status_code = 200
        latency_ms = (time.time() - start) * 1000
        error = ""
    else:
        status_code = 0
        latency_ms = (time.time() - start) * 1000
        error = result.stderr.strip() or "container_unreachable"

    log(env_id, status_code, latency_ms, error)


    # Build the health URL through Nginx
    url = f"http://localhost/env/{env_id}/health"

    start = time.time()
    status_code = 0
    error = ""

    try:
        resp = requests.get(url, timeout=5)
        status_code = resp.status_code
        latency_ms = (time.time() - start) * 1000
    except requests.exceptions.ConnectionError:
        latency_ms = (time.time() - start) * 1000
        error = "connection_refused"
    except requests.exceptions.Timeout:
        latency_ms = 5000
        error = "timeout"
    except Exception as e:
        latency_ms = (time.time() - start) * 1000
        error = str(e)

    log(env_id, status_code, latency_ms, error)

    # Track consecutive failures
    if status_code == 200:
        failure_counts[env_id] = 0
        if state.get("status") == "degraded":
            print(f"  ✓ Environment {env_id} recovered")
            update_status(state_file, "running")
    else:
        failure_counts[env_id] = failure_counts.get(env_id, 0) + 1
        count = failure_counts[env_id]

        if count >= 3:
            print(f"  ⚠ WARNING: {env_id} has failed {count} consecutive checks")
            update_status(state_file, "degraded")


def main():
    print(f"Health poller started (PID: {os.getpid()})")
    print(f"Polling every 30 seconds...")

    while True:
        state_files = list(ENVS_DIR.glob("*.json"))

        if state_files:
            print(f"\n[{datetime.now().strftime('%H:%M:%S')}] "
                  f"Checking {len(state_files)} environment(s)...")
            for state_file in state_files:
                poll_environment(state_file)
        else:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] "
                  f"No active environments")

        time.sleep(30)


if __name__ == "__main__":
    main()
