# Simulator Dev Environment

This repo is the local dev orchestrator for:

- `Simulator` (frontend/server app)
- `database` (API service)
- `redis`

## Prerequisites

- Docker + Docker Compose
- Git
- VS Code (or derivative) + Dev Containers extension (recommended)

## 1. Clone this repo

```bash
git clone https://github.com/twells46/simulator-workspace
cd simulator
```

## 2. Enable the local pre-commit hook

```bash
git config core.hooksPath .githooks
```

## 3. Clone required sibling repos into expected paths

```bash
git clone --recurse-submodules https://github.com/kipr/simulator.git Simulator
git clone https://github.com/kipr/database.git database
```

Required for Simulator runtime assets:

```bash
cd Simulator && git lfs pull && cd ..
```

## 4. Configure environment and secrets

```bash
cp .env.example .env
```

Then update `.env` with your real Firebase/Google values.

Place your service account JSON at `./service_account_key.json` (or set `SERVICE_ACCOUNT_KEY_HOST_FILE` in `.env` to another path).

## 5. Start services

```bash
docker compose up --build -d
```

At this point, `database` and `redis` are running and `devcontainer` is up.

## 6. Start Simulator development processes (inside `devcontainer`)

Open the repo in a Dev Container, then in `/workspace/Simulator` follow the regular [setup procedure](https://github.com/kipr/Simulator).

Simulator is served on `http://localhost:3000`.
