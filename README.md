# Simulator Dev Environment

This repository provides the local Docker Compose and VS Code Dev Container setup for the KIPR Simulator. Application code lives in two sibling repositories; it is not included here.

| Service | Source / image | Purpose | Host endpoint |
| --- | --- | --- | --- |
| `frontend` | `../Simulator`, Node 24 on Debian Trixie | Simulator build tools and manually started Express server | `http://localhost:3113` → container port `3000` |
| `database` | `../database`, Node 24 on Alpine | Database API, compiled into its image | `http://localhost:4000` |
| `redis` | `redis:7-alpine` | API cache with append-only persistence | `localhost:6379` |

Port `8080` is also published for development tooling, but the default frontend command only keeps the container running. `docker compose up` does **not** build or launch the Simulator application.

## Prerequisites

- Docker with Docker Compose (`docker compose`)
- Git, Git LFS, and `patch`
- VS Code (or a compatible editor) with the Dev Containers extension, if using the editor workflow
- Firebase / Google Cloud configuration and a service account JSON for the services you will use

The frontend image includes native build dependencies, Python 3, Java, Git LFS, and the Codex and Serena CLI tools. Run application build commands inside that container.

## 1. Clone the workspace and sibling repositories

```bash
git clone https://github.com/twells46/simulator-workspace.git
cd simulator-workspace
git config core.hooksPath .githooks

cd ..
git clone --recurse-submodules https://github.com/kipr/simulator.git Simulator
git clone https://github.com/kipr/database.git database
git -C Simulator lfs install --local
git -C Simulator lfs pull
cd simulator-workspace
```

Keep these names and relative paths: the Compose build contexts and Containerfile paths depend on them.

```text
parent-directory/
├── simulator-workspace/    # this repository
├── Simulator/              # mounted at /workspace in frontend
└── database/               # copied into the database image at build time
```

For an existing Simulator checkout, also run `git -C ../Simulator submodule update --init --recursive`. Git LFS assets are required for the application to function at runtime.

The local pre-commit hook checks staged files and added lines for likely secrets.

## 2. Configure environment and credentials

From `simulator-workspace`:

```bash
cp .env.example .env
```

Fill in the Firebase database URL, Google Storage bucket, and Google Cloud project ID in `.env`. Place the service account JSON at `./service_account_key.json`, or change `SERVICE_ACCOUNT_KEY_HOST_FILE` to its host path. Both containers mount that file at `/run/secrets/service_account_key`.

The default local service settings are:

- `API_URL=http://database:4000` for the frontend to reach the API over the Compose network.
- `HOST=0.0.0.0` and `PORT=4000` for the database API.
- `REDIS_HOST=redis` and `REDIS_PORT=6379` for the API to reach Redis.

`.env` and `service_account_key.json` are ignored by Git. Compose uses `.env` for variable substitution; only variables listed in each service's `environment` section are passed into that container. Optional variables in `.env.example` are not all wired into the services. Add any needed optional configuration to the relevant service explicitly.

## 3. Apply compatibility patches

Before building, apply the patches from this directory:

```bash
# Close the API server and Redis connection on SIGINT / SIGTERM.
patch --forward -d ../database -p1 < patches/database-shutdown.patch

# Replace distutils in Scratch packaging for the container's newer Python.
patch --forward -d ../Simulator/dependencies/kipr-scratch -p1 < patches/kipr-scratch-remove-distutils.patch
```

These modify the sibling checkouts; neither the container builds nor the Dev Container configuration applies them automatically. If a patch is skipped because it is already applied, continue. For other failures, inspect the target checkout before building.

## 4. Start the development environment

### VS Code Dev Container

The Dev Container configuration bind-mounts two host directories. Create them before opening the container if they do not already exist:

```bash
mkdir -p "$HOME/.config/codex" "$HOME/.serena"
```

Open `simulator-workspace` in VS Code and choose **Dev Containers: Reopen in Container**. This starts all three services and opens the Simulator checkout at `/workspace` as the `node` user. Closing the Dev Container stops the Compose services.

### Docker Compose terminals

Alternatively, start the services and open a frontend shell:

```bash
docker compose up --build -d
docker compose exec frontend bash
```

The shell starts in `/workspace`. Source changes and generated build files there are written to the host's `Simulator` checkout.

## 5. Build the Simulator

Inside `frontend`, in `/workspace`, run the initial setup in this order:

```bash
yarn run build-deps
yarn install
yarn run build-i18n
```

`build-deps` builds the native/WebAssembly dependencies and generates the local `kipr-scratch` package needed by `yarn install`. It downloads toolchains and dependencies and can take considerable time. The current build still uses Yarn; the modernization documents under `plans/` describe proposed changes.

## 6. Run the Simulator

In one frontend terminal, compile in watch mode:

```bash
yarn watch
```

If the build reports `digital envelope routines::unsupported`, use:

```bash
NODE_OPTIONS=--openssl-legacy-provider yarn watch
```

In a second frontend terminal, start Express after the initial compilation finishes:

```bash
node express.js
```

With the Compose terminal workflow, open that second shell using `docker compose exec frontend bash`.

Open **http://localhost:3113** on the host. Express listens on port `3000` inside the container; Compose publishes it as `3113` on the host.

## Everyday commands

Run these from `simulator-workspace` on the host:

```bash
# Inspect service status and API/cache logs.
docker compose ps
docker compose logs -f database redis

# Rebuild and restart the API after changing ../database.
docker compose up -d --build database

# Stop and remove containers, retaining Redis data.
docker compose down
```

Redis data is stored in the named `redis-data` volume. `docker compose down -v` also deletes that data.

Run application checks inside `frontend`, from `/workspace`:

```bash
yarn lint
yarn test
```

## Repository contents

- [docker-compose.yml](docker-compose.yml): services, ports, environment wiring, credentials mount, and Redis volume.
- [simulator.Containerfile](simulator.Containerfile) and [database.Containerfile](database.Containerfile): development toolchain and API image builds.
- [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json): editor setup, host configuration mounts, and forwarded ports.
- [patches/](patches/): local compatibility and shutdown fixes for sibling repositories.
- [plans/BUILD_MODERNIZATION.md](plans/BUILD_MODERNIZATION.md), [plans/GENERAL.md](plans/GENERAL.md), and [plans/INSTANCING_IMPROVEMENTS.md](plans/INSTANCING_IMPROVEMENTS.md): design proposals, not setup steps or guarantees of implemented behavior.
- [redis_replica_disruption_budget.yaml](redis_replica_disruption_budget.yaml): Kubernetes Redis replica disruption budget; not used by local Compose.
- [LICENSE](LICENSE): GNU General Public License, version 3.

See the sibling [Simulator README](../Simulator/README.md) for additional application configuration and build details.
