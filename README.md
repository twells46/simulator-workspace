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

## 5. Test Container build

```bash
docker compose up --build -d
```

If this runs, that means the basic Docker config is still correct.
Close these containers and proceed.

## 6. Start Simulator development (inside `devcontainer`)


### One-time setup

Open the repo in a Dev Container, then in `/workspace/Simulator` follow the regular [setup procedure](https://github.com/kipr/Simulator).
Here for convenience, but refer to the real link for any discrepancies/issues:

Build dependencies:

```bash
yarn run build-deps
```

Install JS dependencies:

```bash
yarn install
```

Build translations:


```bash
yarn run build-i18n
```

### Development workflow

Build in watch mode for development:

```bash
yarn watch
# If you get an error that says "digital envelope routines::unsupported", use:
NODE_OPTIONS=--openssl-legacy-provider yarn watch
```

In another terminal, run the server:

```bash
node express.js
```

Simulator is served on the host (outside Docker) at `http://localhost:3000`.
