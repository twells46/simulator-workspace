# Simulator Dev Environment

This repository provides the local Docker Compose and VS Code Dev Container setup for the KIPR Simulator. Application code lives in two sibling repositories; it is not included here.

| Service | Source / image | Purpose | Host endpoint |
| --- | --- | --- | --- |
| `frontend` | [.devcontainer/Dockerfile](.devcontainer/Dockerfile), Node 24 on Debian Trixie; defined in the [.devcontainer/docker-compose.yml](.devcontainer/docker-compose.yml) overlay | Devcontainer with the Simulator build tools and manually started Express server | `http://localhost:3113` → container port `3000` |
| `database` | `../database`, Node 24 on Alpine | Database API, compiled into its image | `http://localhost:4000` |
| `redis` | `redis:7-alpine` | API cache with append-only persistence | `localhost:6379` |

Port `8080` is also published for development tooling, but the default frontend command only keeps the container running. Plain `docker compose up` starts only `database` and `redis`; `frontend` is part of the devcontainer overlay, and neither builds or launches the Simulator application.

## Prerequisites

- Docker with Docker Compose (`docker compose`)
- Git, Git LFS, and `patch`
- VS Code with the Dev Containers extension, or the `devcontainer` CLI
- Firebase / Google Cloud configuration and a service account JSON for the services you will use

The frontend image includes native build dependencies, Python 3, Java, Git LFS, Claude Code, Codex, and the TypeScript language server. Run application build commands inside that container; the host needs no Node. See [.devcontainer/README.md](.devcontainer/README.md) for the image, mounts, smoke tests, and caveats.

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

Keep these names and relative paths: the Compose build contexts and the devcontainer mounts depend on them.

```text
parent-directory/
├── simulator-workspace/    # this repository
├── Simulator/              # opened in the devcontainer at its host path
└── database/               # copied into the database image at build time
```

For an existing Simulator checkout, also run `git -C ../Simulator submodule update --init --recursive`. Git LFS assets are required for the application to function at runtime.

The local pre-commit hook checks staged files and added lines for likely secrets.

## 2. Configure environment and credentials

From `simulator-workspace`:

```bash
cp .env.example .env
```

Fill in the Firebase database URL, Google Storage bucket, and Google Cloud project ID in `.env`. Place the service account JSON at `./service_account_key.json`, or change `SERVICE_ACCOUNT_KEY_HOST_FILE` to its host path. The `frontend` and `database` containers mount that file at `/run/secrets/service_account_key`.

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

The devcontainer runs as the user `code` and mounts the parent directory at `/workspaces/simulator`; that is its only bind mount. Claude Code and Codex logins are kept in the shared `claude-config` and `codex-config` volumes. Compose fails with a missing-secret error if the service account key from step 2 is absent.

### VS Code

Open `simulator-workspace` in VS Code and choose **Dev Containers: Reopen in Container**. This starts all three services and opens the Simulator checkout at `/workspaces/simulator/Simulator`. Closing the window stops the Compose services.

### Terminal

Start the devcontainer with the `devcontainer` CLI, then open shells in it:

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . fish
```

Source changes and generated build files are written directly to the host checkouts.

## 5. Build the Simulator

Inside `frontend`, in the Simulator checkout, run the initial setup in this order:

```bash
yarn run build-deps
yarn install --cache-folder ./.yarncache
yarn run build-i18n
```

`build-deps` builds the native/WebAssembly dependencies and generates the local `kipr-scratch` package needed by `yarn install`. It downloads toolchains and dependencies and can take considerable time. `--cache-folder` avoids a Yarn race with the `ivygate` Git dependency, as in CI. Build outputs contain absolute paths; if they were built under another path (for example on the host path or the old `/workspace` mount), delete and rebuild them as listed in [AGENTS.md](AGENTS.md#clean-rebuild). The current build still uses Yarn; the modernization documents under `plans/` describe proposed changes.

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

In the terminal workflow, open that second shell with `devcontainer exec --workspace-folder . fish`.

Open **http://localhost:3113** on the host. Express listens on port `3000` inside the container; Compose publishes it as `3113` on the host.

## Everyday commands

Run these from `simulator-workspace` on the host (the container has no Docker CLI):

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

Run application checks inside `frontend`, from the Simulator checkout:

```bash
yarn lint
yarn test
```

## Repository contents

- [docker-compose.yml](docker-compose.yml): the `database` and `redis` services, ports, environment wiring, credentials mount, and Redis volume.
- [database.Containerfile](database.Containerfile): API image build.
- [.devcontainer/](.devcontainer/): development toolchain image, Compose overlay with the `frontend` service, and editor setup; see its [README](.devcontainer/README.md).
- [AGENTS.md](AGENTS.md) and [CLAUDE.md](CLAUDE.md): notes for coding agents (environment detection, build order, clean rebuilds).
- [patches/](patches/): local compatibility and shutdown fixes for sibling repositories.
- [plans/BUILD_MODERNIZATION.md](plans/BUILD_MODERNIZATION.md), [plans/GENERAL.md](plans/GENERAL.md), and [plans/INSTANCING_IMPROVEMENTS.md](plans/INSTANCING_IMPROVEMENTS.md), and [plans/DEVCONTAINER.md](plans/DEVCONTAINER.md): design proposals, not setup steps or guarantees of implemented behavior.
- [redis_replica_disruption_budget.yaml](redis_replica_disruption_budget.yaml): Kubernetes Redis replica disruption budget; not used by local Compose.
- [LICENSE](LICENSE): GNU General Public License, version 3.

See the sibling [Simulator README](../Simulator/README.md) for additional application configuration and build details.
