FROM node:20-bullseye-slim

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    locales \
    wget \
    git \
    git-lfs \
    gnupg \
    cmake \
    build-essential \
    python3 \
    python3-distutils \
    swig \
    zlib1g-dev \
    doxygen \
    default-jre \
    pkg-config \
  && sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
  && locale-gen \
  && update-locale LANG=en_US.UTF-8 \
  && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN mkdir -p /workspace && chown -R node:node /workspace
WORKDIR /workspace

USER node
CMD ["tail", "-f", "/dev/null"]