FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    nghttp2-client \
    iproute2 \
    iputils-ping \
    jq \
    python3 \
    python3-pandas \
    python3-matplotlib \
    bash \
    coreutils \
    gawk \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
