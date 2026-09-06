FROM debian:bookworm-slim

ARG ZIG_VERSION=0.16.0
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        xz-utils \
        ca-certificates \
        qemu-user-static \
    && rm -rf /var/lib/apt/lists/*

RUN ARCH=$(uname -m) \
    && curl -L "https://ziglang.org/download/${ZIG_VERSION}/zig-${ARCH}-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz \
    && tar -xf /tmp/zig.tar.xz -C /usr/local \
    && ln -s /usr/local/zig-${ARCH}-linux-${ZIG_VERSION}/zig /usr/local/bin/zig \
    && rm /tmp/zig.tar.xz

WORKDIR /workspace