FROM node:20-bullseye-slim

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    default-jre \
    doxygen \
    git \
    git-lfs \
    gnupg \
    locales \
    pkg-config \
    python3 \
    python3-distutils \
    swig \
    wget \
    zlib1g-dev \
  && sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
  && locale-gen \
  && update-locale LANG=en_US.UTF-8 \
  && rm -rf /var/lib/apt/lists/*

RUN npm i -g @openai/codex

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN mkdir -p /workspace && chown -R node:node /workspace
WORKDIR /workspace

USER node

RUN wget -qO- https://astral.sh/uv/install.sh | sh
RUN /home/node/.local/bin/uv tool install -p 3.13 serena-agent@latest --prerelease=allow

CMD ["tail", "-f", "/dev/null"]
