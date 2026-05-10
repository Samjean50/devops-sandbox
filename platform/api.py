#!/usr/bin/env python3
# api.py — Control API for the DevOps Sandbox Platform
# Wraps the shell scripts in HTTP endpoints
# Run with: python3 platform/api.py

import os
import json
import subprocess
import time
from pathlib import Path
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

app = FastAPI(title="DevOps Sandbox API")

PROJECT_ROOT = Path(__file__).parent.parent
ENVS_DIR = PROJECT_ROOT / "envs"
LOGS_DIR = PROJECT_ROOT / "logs"
SCRIPTS_DIR = PROJECT_ROOT / "platform"


def load_state(env_id: str) -> dict:
    """Loads environment state from file"""
    state_file = ENVS_DIR / f"{env_id}.json"
    if not state_file.exists():
        raise HTTPException(status_code=404,
                            detail=f"Environment {env_id} not found")
    with open(state_file) as f:
        return json.load(f)


def ttl_remaining(state: dict) -> int:
    """Returns seconds remaining before environment expires"""
    return max(0, state["expires_at"] - int(time.time()))


# ── POST /envs — Create environment ──────────────────────────────────────────
class CreateEnvRequest(BaseModel):
    name: str
    ttl_minutes: int = 30


@app.post("/envs")
def create_env(request: CreateEnvRequest):
    result = subprocess.run(
        [str(SCRIPTS_DIR / "create_env.sh"),
         request.name, str(request.ttl_minutes)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise HTTPException(status_code=500,
                            detail=result.stderr)
    # Extract env ID from output
    env_id = ""
    for line in result.stdout.split("\n"):
        if "ID:" in line:
            env_id = line.split("ID:")[-1].strip()
            break
    return {
        "message": "Environment created",
        "env_id": env_id,
        "output": result.stdout
    }


# ── GET /envs — List active environments ─────────────────────────────────────
@app.get("/envs")
def list_envs():
    envs = []
    for state_file in ENVS_DIR.glob("*.json"):
        try:
            with open(state_file) as f:
                state = json.load(f)
            state["ttl_remaining_seconds"] = ttl_remaining(state)
            envs.append(state)
        except Exception:
            continue
    return {"environments": envs, "count": len(envs)}


# ── DELETE /envs/:id — Destroy environment ────────────────────────────────────
@app.delete("/envs/{env_id}")
def destroy_env(env_id: str):
    load_state(env_id)  # verify exists
    result = subprocess.run(
        [str(SCRIPTS_DIR / "destroy_env.sh"), env_id],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise HTTPException(status_code=500, detail=result.stderr)
    return {"message": f"Environment {env_id} destroyed"}


# ── GET /envs/:id/logs — Last 100 lines of app.log ────────────────────────────
@app.get("/envs/{env_id}/logs")
def get_logs(env_id: str):
    load_state(env_id)
    log_file = LOGS_DIR / env_id / "app.log"
    if not log_file.exists():
        return {"logs": [], "message": "No logs yet"}
    with open(log_file) as f:
        lines = f.readlines()
    return {"logs": lines[-100:], "total_lines": len(lines)}


# ── GET /envs/:id/health — Last 10 health results ─────────────────────────────
@app.get("/envs/{env_id}/health")
def get_health(env_id: str):
    state = load_state(env_id)
    health_file = LOGS_DIR / env_id / "health.log"
    if not health_file.exists():
        return {"health": [], "status": state.get("status")}
    with open(health_file) as f:
        lines = f.readlines()
    return {
        "health": lines[-10:],
        "status": state.get("status"),
        "ttl_remaining_seconds": ttl_remaining(state)
    }


# ── POST /envs/:id/outage — Trigger simulation ────────────────────────────────
class OutageRequest(BaseModel):
    mode: str


@app.post("/envs/{env_id}/outage")
def trigger_outage(env_id: str, request: OutageRequest):
    load_state(env_id)
    result = subprocess.run(
        [str(SCRIPTS_DIR / "simulate_outage.sh"),
         "--env", env_id, "--mode", request.mode],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise HTTPException(status_code=500, detail=result.stderr)
    return {"message": f"Outage simulation '{request.mode}' triggered",
            "output": result.stdout}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
