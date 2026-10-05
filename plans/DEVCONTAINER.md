Rework the dev environment setup in `simulator-workspace/` to match current devcontainer preferences (host-identical user and paths, shared agent state). Be careful: the simulator is tricky to build and has several gotchas.

# Devcontainer rework plan

Drafted on 2026-10-01 from inspection of this repository, `../Simulator`, `../database`, the Simulator build scripts and CI, the host (Bluefin 44, rootful Docker 29, SELinux enforcing), and the reference devcontainers in `Colosseum/colosseum` (Compose-based) and `wombat/firmware-dev`. Nothing has been built or changed yet. `.env` and `service_account_key.json` were not read.

The rework replaces the `node` user and `/workspace` mount with a copy of the host user (`tom`, 1000:1000, home `/var/home/tom`) and mounts the repositories at their host paths. Moving away from `/workspace` is the risky part; see gotcha 1.

## Decisions

1. **Workspace folder:** VS Code still opens `../Simulator`. The parent directory is mounted at its host path so all sibling repositories are reachable.
2. **Codex daemon state:** shared with the host. No volumes overlay `$CODEX_HOME/app-server-control` or `app-server-daemon`.
3. **Git:** signed commits work inside the container. See "Git and signing".
4. **Serena:** removed. Replaced by `typescript-language-server` plus the official `typescript-lsp` Claude Code plugin. Codex keeps its `mcp_servers.serena` entry and will report that the MCP server failed to start; that is accepted.
5. **Agent docs:** add `AGENTS.md`. See "Agent docs".
6. **Frontend without VS Code:** start the devcontainer with VS Code or the `devcontainer` CLI (`brew install devcontainer`). `docker compose exec frontend fish` still works against a running container. Plain `docker compose up` remains fine for `database` and `redis`.

## Gotchas

1. **Leaving `/workspace` invalidates native build outputs.** These contain `/workspace` paths:
   - `dependencies/libkipr_build_c/CMakeCache.txt`
   - `dependencies/kipr-scratch/libwallaby-build/CMakeCache.txt`
   - `dependencies/cpython/builddir/emscripten-browser/Makefile`
   - `dependencies/dependencies.json`

   `dependencies.json` is the dangerous one. `express.js` reads it at runtime to locate `emcc` and libkipr for `/compile`, and `configs/webpack/common.js` reads the CPython and documentation paths. With stale paths CMake refuses to configure, or the server starts and fails only when C is compiled. Rebuild these targets (migration step 3). `dependencies/emsdk` (1.2 GB) holds no `/workspace` paths and is kept; emscripten clears its own cache when its config path changes.
2. **CMake must stay 3.x.** libwallaby declares `cmake_minimum_required(VERSION 3.1)`, which CMake 4 rejects. Debian 13 ships 3.31.6. This is a reason for the base image pin; nothing may install a newer CMake.
3. **Python 3.13.** `build.py` and `kipr-scratch/build.py` probe `python3.12` down to `python3.7`, find none, warn "Python 3.7+ could not be found", and use `python3`. The warning is harmless. `patches/kipr-scratch-remove-distutils.patch` is still required. The CPython 3.12.9 wasm build compiles its own native build Python.
4. **Patches.** `patch --forward` exits 1 when a patch is already applied, so scripts must not treat that as failure. Apply `database-shutdown.patch` before `docker compose build database`; the image copies `src`.
5. **No Docker CLI in the container.** Rebuild the API on the host: `docker compose up -d --build database`.
6. **Compose project name stays `simulator-dev`.** It owns the `simulator-dev_redis-data` volume. `simulator-dev_simulator-codex` is an orphan from an earlier setup.
7. **Current Codex setup is incomplete.** It is mounted at `/home/node/.codex` without `CODEX_HOME`, so absolute paths in `config.toml` and the host-path project trust entries do not apply. The uncommitted `seccomp:unconfined` is not enough for its sandbox: `bubblewrap` and `systempaths=unconfined` are missing.
8. **Shared Codex daemon state (decision 2).** The host Codex app-server daemon keeps sockets and PID state in `$CODEX_HOME/app-server-*`. The container sees them across a PID namespace boundary. If container Codex misbehaves (cannot reach or replaces the host daemon), the fallback is the `firmware-dev` approach: named volumes over those two directories.
9. **`~/.serena` does not exist on the host,** so the current config cannot start without the README's `mkdir`. Moot once Serena is removed.
10. **Git config is XDG** (`~/.config/git/config`); VS Code only copies `~/.gitconfig`. The GitHub credential helper is hard-coded to `/home/linuxbrew/.linuxbrew/bin/gh`, and `commit.gpgsign=true` with an OpenPGP key.
11. **Claude status line runs `jq`.**
12. **Wasted build context.** The dev image builds with context `../Simulator` (LFS assets, CPython source) but copies nothing from it.
13. **Ports.** `forwardPorts` 4000 and 6379 point at the `frontend` container's localhost, where nothing listens; Compose already publishes them. Host ports 3113, 8080, 4000, and 6379 are published; 6379 clashes with a local Redis. Port 8080 (webpack-dev-server default, `yarn start-dev`) is not part of the documented workflow and is untested.
14. **SELinux.** Bind mounts work today only because dockerd is not SELinux-enabled. Add `label=disable` so they keep working if that changes.
15. **Bluefin home.** `$HOME` is `/var/home/tom` and `/home` is a symlink to `var/home`. Use `/var/home` paths; Claude project keys use `-var-home-…`. Make `/home` a symlink to `var/home` in the image so `/home/...` paths (e.g. the linuxbrew `gh` helper) resolve as on the host.
16. **No `build-deps` in `postCreateCommand`.** It is long (CPython to wasm), needs the network, and depends on patches being applied first. Use `yarn install --cache-folder ./.yarncache` (CI's workaround for a yarn race with the `ivygate` Git dependency).
17. **`node_modules` needs no reinstall** for the path change: no absolute paths, and the host has no Node.

## Design

Compose-based, following `Colosseum/colosseum`. The `frontend` service stays in the base compose file; the overlay adds only devcontainer concerns.

```
simulator-workspace/
  docker-compose.yml        # frontend/database/redis; frontend built from .devcontainer, no /workspace mount
  database.Containerfile    # unchanged
  AGENTS.md                 # new
  CLAUDE.md                 # new: @AGENTS.md
  .devcontainer/
    Dockerfile              # replaces simulator.Containerfile (deleted)
    docker-compose.yml      # overlay on frontend
    devcontainer.json
    README.md
```

### Base `docker-compose.yml`

- `frontend.build`: context `.devcontainer`, dockerfile `Dockerfile`.
- Remove the `../Simulator:/workspace` volume and `working_dir: /workspace`.
- Move the uncommitted `security_opt` to the overlay.
- Keep `name: simulator-dev`, `init: true`, environment, secrets, ports, `depends_on`, and the `database`/`redis` services unchanged.

### `.devcontainer/Dockerfile`

- `FROM node:24.21.0-trixie-slim`. Node 24 and Debian 13 are the proven combination; Debian 13 is also the CMake 3.x pin (gotcha 2). The production `Simulator/Dockerfile` uses Node 20; note the mismatch in a comment.
- Toolchain (unchanged): build-essential, cmake, default-jre (scratch-blocks closure compiler), doxygen, git, git-lfs, locales (en_US.UTF-8), pkg-config, python3, swig, wget, zlib1g-dev.
- Dev tools: ca-certificates, curl, fd-find (symlinked to `fd`), fish, fzf, jq (status line), openssh-client, ripgrep, sudo, tzdata (`TZ=America/Chicago`).
- Services and agents: bubblewrap (Codex sandbox), redis-tools (`redis-cli`), gnupg (signing), gh (credential helper).
- `/home` becomes a symlink to `var/home`; `ln -s /usr/bin/gh /var/home/linuxbrew/.linuxbrew/bin/gh` so the host's credential helper path resolves.
- `userdel -r node` (it holds UID 1000), then create `$USERNAME` with `$USER_UID:$USER_GID`, home `$USER_HOME`, fish, passwordless sudo.
- Global npm, root, with versions checked in the same `RUN`: `@openai/codex`, `typescript-language-server`, `typescript` (pinned). The language server prefers the workspace's own `node_modules/typescript` (4.9); the global one is a fallback.
- Claude Code via the native installer as the user, `claude --version` in the same `RUN`, `~/.local/bin` on `PATH`.
- No uv or Serena.
- `CMD ["sleep", "infinity"]`.

### `.devcontainer/docker-compose.yml` (overlay on `frontend`)

Build paths resolve relative to the base compose file; say so in a comment.

- Build args: `USERNAME: ${USER:-code}`, `USER_HOME: ${HOME:-/home/code}`, `USER_UID: ${LOCAL_UID:-1000}`, `USER_GID: ${LOCAL_GID:-1000}`.
- Bind `${HOME}/.config/codex` at the same path, `create_host_path: false`; `CODEX_HOME: ${HOME}/.config/codex`.
- `security_opt`: `seccomp=unconfined`, `systempaths=unconfined`, `label=disable`.
- `command: sleep infinity`.

### `.devcontainer/devcontainer.json`

- `dockerComposeFile: ["../docker-compose.yml", "docker-compose.yml"]`, `service: frontend`, `runServices: [redis, database, frontend]`, `shutdownAction: stopCompose`.
- Mounts, all at host-identical paths: `${localWorkspaceFolder}/..` (Simulator, database, this repo, `old/`), `~/.claude`, `~/.claude.json`, `~/.config/git`, `~/.config/gh`.
- `workspaceFolder: ${localWorkspaceFolder}/../Simulator`. Verify VS Code and terminals show a normalized path; Claude's project key depends on it.
- `remoteUser: ${localEnv:USER}`, `updateRemoteUserUID: false`.
- `initializeCommand`: create `~/.claude`, `~/.config/codex`, `~/.config/git`, `~/.config/gh`, touch `~/.claude.json`; fail with a clear message if `.env` or the service account key is missing (Compose otherwise fails with a cryptic secrets error).
- `postStartCommand`: bounded wait (about 60 s, then warn and continue) for `redis-cli -h redis ping` and an HTTP response from `database:4000`, so bad Firebase credentials cannot hang startup.
- No `postCreateCommand` (gotcha 16).
- No `forwardPorts`; Compose publishes them (Express is `localhost:3113`).
- Extensions: `anthropic.claude-code`, `openai.chatgpt`, `dbaeumer.vscode-eslint`, `github.vscode-pull-request-github`, `rvest.vs-code-prettier-eslint` (the formatter in `Simulator/.vscode/settings.json`).
- Fish as the default terminal profile.

### Git and signing

- `~/.config/git` is mounted, so name, email, signing key, `commit.gpgsign`, and LFS filters match the host. `~/.config/gh` is mounted for the `gh auth git-credential` helper.
- First approach: VS Code's built-in GPG agent forwarding (needs `gnupg` in the image). Verify with `echo test | gpg --clearsign` and `git commit --allow-empty -S -m test` on a scratch branch. Signing then works only while VS Code is attached, and pinentry appears on the host.
- If the public key is missing or forwarding fails: mount `~/.gnupg` and the host's `S.gpg-agent.extra` socket at the path `gpgconf --list-dirs agent-socket` reports inside the container (watch directory ownership and the 700 mode gpg requires).

### Claude Code TypeScript LSP

- Install the plugin from the existing `claude-plugins-official` marketplace: `claude plugin install typescript-lsp@claude-plugins-official`. Prefer local scope in `Simulator` so other projects and host sessions are unaffected; confirm the resulting settings file is not committed to the upstream Simulator repo.
- The host has no Node, so the plugin's `typescript-language-server` only works inside the container.
- Verify by asking Claude for a definition or references in a `.ts` file inside the container.

### Agent docs

- `simulator-workspace/AGENTS.md`, with `CLAUDE.md` containing `@AGENTS.md`. Contents:
  - Environment detection: `/.dockerenv`, `REMOTE_CONTAINERS`/`DEVCONTAINER`, user home `/var/home/tom`, repositories at host paths.
  - Provided: `redis` and `database` services, `API_URL` and `FIREBASE_SERVICE_ACCOUNT_KEY_FILE` preset, secret at `/run/secrets/service_account_key`.
  - Not available: Docker CLI (database rebuilds and `docker compose` are host-only). Report the specific limitation observed instead of concluding a tool or service does not exist.
  - Build commands and order, patch steps, the clean-rebuild list from gotcha 1.
- Reach: Claude loads `CLAUDE.md` from the working directory's ancestors and Codex reads `AGENTS.md` only up to the git root, so sessions in `Simulator` or `database` will not see this file. Proposed: symlink `../CLAUDE.md` (the shared parent) to it so Claude in any sibling picks it up. For Codex in `Simulator`, an `AGENTS.md` symlink listed in `Simulator/.git/info/exclude` would work without touching the upstream repo; confirm before adding.

### Documentation

- New `.devcontainer/README.md`: image contents and why, Host | Container | Why mount table, opening (VS Code, `devcontainer up --workspace-folder .`), standalone `docker compose ... build frontend`, rebuild triggers, smoke tests for Claude, Codex, the LSP, and signing, caveats (security options, shared agent state written concurrently by host and container, published host ports, Codex Serena MCP error).
- Update the top-level `README.md`: no `/workspace`; the Compose-terminal workflow becomes "start via VS Code or the `devcontainer` CLI, then `docker compose exec frontend fish`"; drop the Serena and `~/.serena` steps; database rebuilds on the host.

## Migration

1. Fold the two uncommitted diffs into the rework, then run:
   ```sh
   docker compose -f docker-compose.yml -f .devcontainer/docker-compose.yml config --quiet
   LOCAL_UID=$(id -u) LOCAL_GID=$(id -g) \
     docker compose -f docker-compose.yml -f .devcontainer/docker-compose.yml build frontend
   ```
2. Reopen in the container. Check:
   - `claude --version`, and the status line renders;
   - `codex --version`, `codex login status`, `codex sandbox -- true`;
   - `typescript-language-server --version`, `git lfs version`, `gh auth status`;
   - `pwd` is the host path of `Simulator`.
3. In `Simulator`, remove only the stale outputs and rebuild:
   ```sh
   rm -rf dependencies/{libkipr_build_c,libkipr_build_python,libkipr_install_c,dependencies.json} \
          dependencies/cpython/builddir dependencies/kipr-scratch/libwallaby-build
   yarn run build-deps
   yarn install --cache-folder ./.yarncache
   yarn run build-i18n
   yarn lint
   yarn test
   NODE_OPTIONS=--openssl-legacy-provider yarn build
   ```
   Fallback if the rebuild cannot be done: a `/workspace` symlink in the image. Not recommended; it hides stale paths.
4. Runtime check:
   - `dependencies/dependencies.json` shows host paths;
   - `yarn watch` and `node express.js`, then open `http://localhost:3113`;
   - compile and run a C program and a Python program in the UI (exercises `emcc`/libkipr and the CPython build).
5. Signing and LSP checks from the sections above.
6. With approval, remove the orphaned `simulator-dev_simulator-codex` volume.

## Noticed, outside this scope

- `plans/GENERAL.md` is byte-identical to `plans/BUILD_MODERNIZATION.md`.
- `Simulator/.gitmodules` locally points libwallaby at `MakerYuichi/libwallaby` branch `fix/cleanup-siof-211`. The rebuild uses whatever is checked out in `dependencies/libwallaby`.
- `Simulator/eslint.config.mjs` hard-codes `tsconfigRootDir: "/home/tom/kipr_sources/Simulator"`. ESLint 7 ignores that file, so it is harmless for now.
