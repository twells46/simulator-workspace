# Simulator workspace

The KIPR Simulator workspace is the directory that holds three repositories (mounted at `/workspaces/simulator` in the devcontainer):

- `simulator-workspace`: Docker Compose and devcontainer setup. This file lives there; it is also linked as `CLAUDE.md` in the parent directory and as `Simulator/AGENTS.md` (excluded locally, not committed upstream).
- `Simulator`: frontend, Express server, and native/wasm dependencies.
- `database`: database API.

Paths below are relative to the workspace directory unless a command says otherwise. Setup is in `simulator-workspace/README.md`; the container is described in `simulator-workspace/.devcontainer/README.md`.

## Environment detection

You are in the devcontainer (the Compose `frontend` service) when `/.dockerenv` exists and `DEVCONTAINER=true` (VS Code also sets `REMOTE_CONTAINERS=true`). The user is `code` with home `/home/code`, and the workspace directory is mounted at `/workspaces/simulator`, so absolute paths differ from the host's. Claude Code and Codex state is in shared named volumes (`~/.claude`, `~/.codex`), separate from the host's.

Provided in the container:

- `redis` (`redis-cli -h redis`) and `database` (`http://database:4000`) Compose services.
- `API_URL` and `FIREBASE_SERVICE_ACCOUNT_KEY_FILE` preset; the service account key is at `/run/secrets/service_account_key`.
- Node 24, Yarn 1, CMake 3.31, Python 3.13, Java, Git LFS, `gh`, `gpg`, Claude Code, Codex, `typescript-language-server`.

Not available in the container:

- The Docker CLI and socket. `docker compose` commands, including rebuilding the database API image, run on the host only.
- Host-only tools such as Homebrew, and the host's home directory (agent settings, Git and `gh` configuration).

If a command fails, report the specific limitation you observed (missing binary, no socket, unreachable host, failed credentials) instead of concluding that a tool or service does not exist.

On the host there is no Node, so the Simulator build, tests, and `typescript-language-server` work only inside the container.

## Building the Simulator

Apply the patches first, on the host or in the container, from `simulator-workspace` (the commands use paths relative to it). `patch --forward` exits 1 when a patch is already applied; that is not a failure.

```sh
patch --forward -d ../database -p1 < patches/database-shutdown.patch
patch --forward -d ../Simulator/dependencies/kipr-scratch -p1 < patches/kipr-scratch-remove-distutils.patch
```

Apply `database-shutdown.patch` before building the database image, which copies `src`.

Then, in the container, from `Simulator`, in this order:

```sh
yarn run build-deps                      # emsdk, libkipr, CPython to wasm, kipr-scratch; long, needs the network
yarn install --cache-folder ./.yarncache # the cache folder avoids a yarn race with the ivygate Git dependency
yarn run build-i18n
yarn lint
yarn test
NODE_OPTIONS=--openssl-legacy-provider yarn build
```

`build.py` warns "Python 3.7+ could not be found" and falls back to `python3`; that is expected.

Run the app with `yarn watch` in one terminal and `node express.js` in another, then open `http://localhost:3113` on the host.

### Clean rebuild

These outputs contain absolute paths. From `Simulator`, delete and rebuild them (`yarn run build-deps`) if the checkout moves or they were built at another path (for example on the host path or the old `/workspace` mount):

```sh
rm -rf dependencies/{libkipr_build_c,libkipr_build_python,libkipr_install_c,dependencies.json} \
       dependencies/cpython/builddir dependencies/kipr-scratch/libwallaby-build
```

`dependencies/dependencies.json` matters most: `express.js` reads it to find `emcc` and libkipr for `/compile`, and `configs/webpack/common.js` reads the CPython and documentation paths. Stale paths make the server fail only when C code is compiled. `dependencies/emsdk` can be kept.

## Database API

After changing `database`, rebuild it on the host from `simulator-workspace`:

```sh
docker compose up -d --build database
```
