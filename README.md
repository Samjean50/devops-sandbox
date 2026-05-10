# DevOps Sandbox Platform

A self-service platform for spinning up isolated temporary environments,
simulating outages, monitoring health, and auto-destroying on TTL expiry.

## Architecture
                ┌─────────────────────────────────┐
                │         Host Machine             │
                │                                  │
HTTP :80  ───────►│  platform-nginx                  │
│    └── /env/{id}/ ──► app        │
API  :8000 ──────►│  platform-api                    │
│  platform-monitor (health polls) │
│  cleanup_daemon (TTL watchdog)   │
│                                  │
│  ┌──────────────────────────┐   │
│  │  Environment env-abc123   │   │
│  │  ┌────────────────────┐  │   │
│  │  │  sandbox-app:5000  │  │   │
│  │  └────────────────────┘  │   │
│  │  Docker network: env-abc  │   │
│  └──────────────────────────┘   │
└─────────────────────────────────┘

## Prerequisites

- Docker 24+
- Docker Compose v2+
- Python 3.8+
- make

## Quick Start

```bash
# 1. Clone and build
git clone https://github.com/Samjean50/devops-sandbox.git
cd devops-sandbox
make build

# 2. Start the platform
make up

# 3. Create your first environment
./platform/create_env.sh myapp 30

# 4. Test it
curl http://localhost/env/env-myapp-XXXXX/health
```

## Make Targets

| Command | Description |
|---------|-------------|
| `make up` | Start Nginx, API, monitor, cleanup daemon |
| `make down` | Stop everything, destroy all envs |
| `make build` | Build the sandbox-app Docker image |
| `make create` | Interactive environment creation |
| `make destroy ENV=<id>` | Destroy specific environment |
| `make logs ENV=<id>` | Tail environment app logs |
| `make health` | Show all environment health statuses |
| `make simulate ENV=<id> MODE=<mode>` | Run outage simulation |
| `make clean` | Wipe all state and logs |

## Outage Simulation Modes

| Mode | Description |
|------|-------------|
| `crash` | Hard kills the container |
| `pause` | Freezes the container |
| `network` | Disconnects from platform network |
| `recover` | Restores whatever was broken |
| `stress` | CPU stress test (requires stress-ng) |

## Full Demo Walkthrough

```bash
# Create environment
./platform/create_env.sh myapp 30
ENV_ID=env-myapp-XXXXXX

# Check health
curl http://localhost/env/$ENV_ID/health

# Simulate crash
make simulate ENV=$ENV_ID MODE=crash

# Watch health monitor detect it
tail -f logs/$ENV_ID/health.log

# Recover
make simulate ENV=$ENV_ID MODE=recover

# Check logs
make logs ENV=$ENV_ID

# Destroy manually
make destroy ENV=$ENV_ID

# Or wait for auto-destroy when TTL expires
tail -f logs/cleanup.log
```

## Known Limitations

- Runs on a single host — no multi-node support
- Log shipping uses docker logs -f (Approach A) — may miss logs if shipper dies
- Port allocation is random — small chance of collision under heavy load
- Nginx routing uses resolver — brief delay on first request after container restart
- Mac users: cleanup daemon uses Linux date syntax — minor TTL display difference
