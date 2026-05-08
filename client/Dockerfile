FROM alpine/curl-http3:8.11.0

USER root

RUN apk add --no-cache \
    bash \
    ca-certificates \
    coreutils \
    gawk \
    iproute2 \
    iputils \
    jq \
    nghttp2 \
    py3-matplotlib \
    py3-pandas \
    python3

WORKDIR /workspace
