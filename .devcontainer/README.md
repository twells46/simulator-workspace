# Simulator devcontainer

The devcontainer is the Compose `frontend` service, defined in the `docker-compose.yml` overlay here on top of `../docker-compose.yml` (`database` and `redis`). It mounts the parent directory at `/workspaces/simulator` and opens `Simulator` in VS Code. Build and run the Simulator here.

It needs nothing from the host except the workspace: no host home directories are mounted, and the image builds without build arguments.

## Image

`Dockerfile`, based on `node:24.21.0-trixie-slim`:

- **Base pin.** Node 24 on Debian 13 is the combination the Simulator build is known to work with. Debian 13 ships CMake 3.31; libwallaby's `cmake_minimum_required(VERSION 3.1)` is rejected by CMake 4, so nothing may install a newer CMake. The production `Simulator/Dockerfile` uses Node 20.
- **Build toolchain:** build-essential, cmake, default-jre (scratch-blocks closure compiler), doxygen, git, git-lfs, locales (en_US.UTF-8), pkg-config, python3 (3.13), swig, wget, zlib1g-dev.
- **Dev tools:** ca-certificates, curl, fd (`fd-find`), fish, fzf, jq (Claude status line), openssh-client, ripgrep, sudo, tzdata (`America/Chicago`).
- **Services and agents:** bubblewrap (agent sandboxes), redis-tools, gnupg (commit signing), gh.
- **Global npm:** Codex, `typescript-language-server`, and TypeScript 6.0.3 as a fallback for the language server (TypeScript 7 ships no `tsserver`; the workspace's own TypeScript 4.9 is preferred).
- **Claude Code** via the native installer, in `~/.local/bin`.
- **`wait-for-services`**, copied from `wait-for-services.sh`.
- **User:** `code`, UID/GID 1000, home `/home/code`, fish, passwordless sudo. The image's `node` user (UID 1000) is removed to make room. The name and home are fixed because the shared agent volumes hold absolute paths. On a host where your UID is not 1000, the devcontainer CLI and VS Code remap it.

## Mounts

| Source | Container | Why |
| --- | --- | --- |
| `../` (`Simulator`, `database`, `simulator-workspace`) | `/workspaces/simulator` | The workspace; the only bind mount |
| `claude-config` volume | `/home/code/.claude` (`CLAUDE_CONFIG_DIR`) | Claude Code login and state |
| `codex-config` volume | `/home/code/.codex` (`CODEX_HOME`) | Codex login and state |
| `service_account_key.json` | `/run/secrets/service_account_key` | Compose secret for Firebase |

The two agent volumes have fixed names and are shared with every other devcontainer on the machine that follows the same convention: log in once and each container reuses it. Host agent configuration (user settings, skills, plugins, memories, sessions) is deliberately not shared; project configuration (`AGENTS.md`, `.claude/`) arrives with the workspace.

Git identity and credentials need no mounts under VS Code, which copies the host Git config into the container and forwards its credential helper and the SSH and GPG agents.

## Opening

Create `../.env` and the service account key first (see the [workspace README](../README.md#2-configure-environment-and-credentials)); without them Compose fails with a missing-secret error.

- VS Code: open `simulator-workspace` and run **Dev Containers: Reopen in Container**.
- CLI, from `simulator-workspace`:

  ```sh
  devcontainer up --workspace-folder .
  devcontainer exec --workspace-folder . fish
  ```

On each start, `wait-for-services` waits up to 60 s for `redis` and `database:4000`, then warns and continues.

## Building

See [AGENTS.md](../AGENTS.md#building-the-simulator) for the patch steps, build order, and clean-rebuild list. In short, from `/workspaces/simulator/Simulator`:

```sh
yarn run build-deps
yarn install --cache-folder ./.yarncache
yarn run build-i18n
yarn lint
yarn test
NODE_OPTIONS=--openssl-legacy-provider yarn build
```

Build outputs hold absolute paths. Outputs built under another mount path (the earlier host-identical path, or `/workspace`) must be deleted and rebuilt as described there.

To build the image and run a command without VS Code, from `simulator-workspace`:

```sh
docker build .devcontainer            # the image alone
alias dc='docker compose -f docker-compose.yml -f .devcontainer/docker-compose.yml'
dc config --quiet
dc build frontend
dc run --rm -w /workspaces/simulator/Simulator frontend yarn test
```

Rebuild the container (**Dev Containers: Rebuild Container**, or `devcontainer up --workspace-folder . --remove-existing-container`) after changing the `Dockerfile`, `wait-for-services.sh`, or either compose file.

## Agents: first login and smoke tests

Once per machine (the login is stored in the shared volumes):

```sh
claude            # then /login
codex login
```

Then:

```sh
pwd                                  # /workspaces/simulator/Simulator
claude --version
codex --version && codex login status && codex sandbox -- true
typescript-language-server --version
git lfs version
redis-cli -h redis ping && curl -s -o /dev/null -w '%{http_code}\n' http://database:4000/
```

**Signing.** VS Code forwards the host GPG agent while it is attached; pinentry appears on the host. Outside VS Code, signed commits do not work.

**TypeScript LSP.** The language server is in the image, but Claude Code plugins live in the `claude-config` volume: install `typescript-lsp@claude-plugins-official` once inside the container.

## Caveats

- **Security options.** `seccomp=unconfined` (bubblewrap, used by the Claude Code and Codex sandboxes) and `systempaths=unconfined` (Codex's sandbox mounts its own `/proc`; verified to fail without it) disable Docker's syscall filter and its masked/read-only system paths for `frontend`.
- **Shared agent state.** Containers share the agent volumes live, so concurrent sessions in two containers write the same files.
- **MCP servers and hooks** configured inside the volumes need their executables in the image.
- **Published ports.** Compose publishes 3113 (Express), 8080 (webpack-dev-server, untested), 4000 (database API), and 6379 (Redis) on the host. Stop a local Redis or other service using those ports first.
- **Git outside VS Code.** With `devcontainer exec` or `docker compose exec` there is no forwarded identity or credential helper; set `user.name`/`user.email` and run `gh auth login && gh auth setup-git` in the container if you push from there.
- **SELinux.** With Docker on Fedora (enforcing) the workspace mount works unlabeled. With Podman, or a Docker daemon with SELinux enabled, add `label=disable` to `security_opt`.
- **No Docker CLI** in the container. Rebuild the API on the host with `docker compose up -d --build database`.
- The Compose project name `simulator-dev` owns the `simulator-dev_redis-data` volume; keep it.
