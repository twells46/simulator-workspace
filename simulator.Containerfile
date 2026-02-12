FROM node:20-bullseye-slim

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    wget \
    git \
    cmake \
    build-essential \
    python3 \
    python3-distutils \
    swig \
    zlib1g-dev \
    doxygen \
    default-jre \
    pkg-config \
  && rm -rf /var/lib/apt/lists/*

# RUN npm install -g yarn

RUN mkdir -p /workspace && chown -R node:node /workspace
WORKDIR /workspace

USER node

CMD ["tail", "-f", "/dev/null"]
