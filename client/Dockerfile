FROM alpine:3.20 AS h2load-builder

ARG AWSLC_VERSION=v1.72.0
ARG NGHTTP3_VERSION=v1.15.0
ARG NGTCP2_VERSION=v1.22.1
ARG NGHTTP2_VERSION=v1.69.0
ARG BUILD_JOBS=1

RUN apk add --no-cache \
    autoconf \
    automake \
    bison \
    c-ares-dev \
    clang \
    cmake \
    g++ \
    git \
    libev-dev \
    libtool \
    linux-headers \
    make \
    musl-dev \
    openssl-dev \
    pkgconf \
    zlib-dev

WORKDIR /build

RUN git clone --depth 1 --recursive --shallow-submodules -b "${AWSLC_VERSION}" https://github.com/aws/aws-lc \
    && cmake -S aws-lc -B aws-lc/build -DDISABLE_GO=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/aws-lc \
    && make -j"${BUILD_JOBS}" -C aws-lc/build \
    && cmake --install aws-lc/build

RUN git clone --depth 1 --recursive --shallow-submodules -b "${NGHTTP3_VERSION}" https://github.com/ngtcp2/nghttp3 \
    && cd nghttp3 \
    && autoreconf -i \
    && ./configure --prefix=/opt/nghttp3 --enable-lib-only \
    && make -j"${BUILD_JOBS}" \
    && make install

RUN git clone --depth 1 --recursive --shallow-submodules -b "${NGTCP2_VERSION}" https://github.com/ngtcp2/ngtcp2 \
    && cd ngtcp2 \
    && autoreconf -i \
    && PKG_CONFIG_PATH=/opt/aws-lc/lib/pkgconfig ./configure \
        --prefix=/opt/ngtcp2 \
        --enable-lib-only \
        --with-boringssl \
        BORINGSSL_CFLAGS="-I/opt/aws-lc/include" \
        BORINGSSL_LIBS="-L/opt/aws-lc/lib -lssl -lcrypto" \
    && make -j"${BUILD_JOBS}" \
    && make install

RUN set -eux \
    && git config --global http.version HTTP/1.1 \
    && for i in 1 2 3; do \
        git clone --depth 1 --recursive -b "${NGHTTP2_VERSION}" https://github.com/nghttp2/nghttp2 && break; \
        echo "nghttp2 clone failed (attempt ${i}), retrying..." >&2; \
        rm -rf nghttp2; \
        if [ "${i}" = "3" ]; then exit 1; fi; \
        sleep 3; \
      done \
    && cd nghttp2 \
    && autoreconf -i \
    && PKG_CONFIG_PATH="/opt/aws-lc/lib/pkgconfig:/opt/nghttp3/lib/pkgconfig:/opt/ngtcp2/lib/pkgconfig" \
       OPENSSL_CFLAGS="-I/opt/aws-lc/include" \
       OPENSSL_LIBS="-L/opt/aws-lc/lib -lssl -lcrypto" \
       LDFLAGS="-Wl,-rpath,/opt/aws-lc/lib -Wl,-rpath,/opt/nghttp3/lib -Wl,-rpath,/opt/ngtcp2/lib" \
       ./configure \
        --prefix=/opt/nghttp2 \
        --enable-app \
        --enable-http3 \
        --disable-python-bindings \
        --disable-examples \
        --without-libxml2 \
        --without-jemalloc 2>&1 | tee /tmp/nghttp2-configure.log \
    && grep -E "HTTP/3([[:space:]]+\\(EXPERIMENTAL\\))?:[[:space:]]+yes" /tmp/nghttp2-configure.log \
    && make -j"${BUILD_JOBS}" \
    && make install

FROM alpine/curl-http3:8.11.0

USER root

RUN apk add --no-cache \
    bash \
    ca-certificates \
    c-ares \
    coreutils \
    gawk \
    iproute2 \
    iputils \
    jq \
    libev \
    libstdc++ \
    py3-matplotlib \
    py3-pandas \
    python3 \
    zlib

COPY --from=h2load-builder /opt/aws-lc /opt/aws-lc
COPY --from=h2load-builder /opt/nghttp3 /opt/nghttp3
COPY --from=h2load-builder /opt/ngtcp2 /opt/ngtcp2
COPY --from=h2load-builder /opt/nghttp2 /opt/nghttp2
RUN ln -s /opt/nghttp2/bin/h2load /usr/local/bin/h2load

ENV LD_LIBRARY_PATH=/opt/aws-lc/lib:/opt/nghttp3/lib:/opt/ngtcp2/lib:/opt/nghttp2/lib

WORKDIR /workspace
