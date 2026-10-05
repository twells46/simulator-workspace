# Node 24 on Debian 13 is the combination the Simulator build is known to work
# with. Debian 13 also pins CMake to 3.31: libwallaby declares
# cmake_minimum_required(VERSION 3.1), which CMake 4 rejects, so nothing here
# may install a newer CMake. (The production Simulator/Dockerfile uses Node 20.)
FROM node:24.21.0-trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=America/Chicago

# Simulator build toolchain (dependencies/build.py, kipr-scratch):
#   default-jre: closure compiler for scratch-blocks
#   doxygen, swig: libkipr documentation and Python bindings
# Dev tools:
#   fd-find: Debian ships the binary as fdfind (symlinked to fd below)
#   jq: the Claude Code status line
# Services and agents:
#   bubblewrap: Codex's Linux sandbox
#   gh: pull requests and `gh auth git-credential` outside VS Code
#   gnupg: signed commits through VS Code's GPG agent forwarding
#   redis-tools: redis-cli against the Compose redis service
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bubblewrap \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    default-jre \
    doxygen \
    fd-find \
    fish \
    fzf \
    gh \
    git \
    git-lfs \
    gnupg \
    jq \
    locales \
    openssh-client \
    pkg-config \
    python3 \
    redis-tools \
    ripgrep \
    sudo \
    swig \
    tzdata \
    wget \
    zlib1g-dev \
  && ln -s "$(command -v fdfind)" /usr/local/bin/fd \
  && sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
  && locale-gen \
  && update-locale LANG=en_US.UTF-8 \
  && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Codex and the TypeScript language server for the Claude Code typescript-lsp
# plugin. The server prefers the workspace's own node_modules/typescript; the
# global one is a fallback. TypeScript 7 ships no tsserver, so stay on 6.x.
RUN npm install -g @openai/codex typescript-language-server typescript@6.0.3 \
  && codex --version \
  && typescript-language-server --version \
  && tsc --version \
  && npm cache clean --force

# Runs on each start (devcontainer.json postStartCommand).
COPY --chmod=755 wait-for-services.sh /usr/local/bin/wait-for-services

# The image's `node` user holds UID/GID 1000; remove it so the fixed `code` user
# can take them. The user and home are the same in every devcontainer because
# the shared agent volumes hold absolute paths.
RUN userdel -r node \
  && groupadd --gid 1000 code \
  && useradd --uid 1000 --gid 1000 --create-home --shell /usr/bin/fish code \
  && echo 'code ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/code \
  && chmod 0440 /etc/sudoers.d/code

USER code
WORKDIR /home/code

# Agent state lives in named volumes; a new volume inherits this ownership.
# CLAUDE_CONFIG_DIR also moves ~/.claude.json inside the volume.
# DEVCONTAINER lets agents and scripts detect the container, also under
# `docker compose exec` (VS Code alone sets REMOTE_CONTAINERS).
ENV CLAUDE_CONFIG_DIR=/home/code/.claude \
    CODEX_HOME=/home/code/.codex \
    DEVCONTAINER=true \
    PATH=/home/code/.local/bin:$PATH
RUN mkdir -p "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" \
  && curl -fsSL https://claude.ai/install.sh | bash \
  && claude --version

CMD ["sleep", "infinity"]
