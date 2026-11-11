# Base image for Orca workspace containers. Toolchain and system packages only:
# the Orca plugin adds sshd, the dev user (uid 1000), agent CLIs and Podman,
# copies the repo to /home/dev/spec-kit and runs ORCA_SYNC_COMMAND there as dev.
FROM ubuntu:24.04

# git: the test suite runs git in many tests. ca-certificates: uv downloads Python over HTTPS.
# curl and xz-utils: fetch and unpack the Node.js tarball below. libatomic1: Node's runtime dependency.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git libatomic1 xz-utils \
 && rm -rf /var/lib/apt/lists/*

# Node.js 26.13.0, the latest stable release (LTS line "Lithium"), from the official
# tarball. The SHA-256 of each architecture's tarball is checked before unpacking.
# To upgrade, change NODE_VERSION and both checksums from
# https://nodejs.org/dist/vX.Y.Z/SHASUMS256.txt.
# /opt/node is owned by uid 1000 so the dev user can run `npm install -g`.
ARG TARGETARCH
ARG NODE_VERSION=26.13.0
RUN case "$TARGETARCH" in \
      amd64) NODE_ARCH=x64;   NODE_SHA=d28a96af6c38596f6d9d97c0ee531c13d238d757742387d1928de822d959e997 ;; \
      arm64) NODE_ARCH=arm64; NODE_SHA=406fe3fbde1c054adff8b297c16fdb5af6659db327c1ac8acd46b56ef1af9a92 ;; \
      *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
 && echo "${NODE_SHA}  /tmp/node.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/node \
 && tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1 \
 && rm /tmp/node.tar.xz \
 && chown -R 1000:1000 /opt/node

# uv installs the Python the project needs (requires-python >=3.11; CI tests 3.13 and 3.14).
COPY --from=ghcr.io/astral-sh/uv:0.13.7 /uv /uvx /usr/local/bin/

# Shared venv and shared uv-managed Python. Orca checks out linked worktrees at other
# paths, and each one reuses these dependencies, so neither lives under /home/dev.
RUN mkdir -p /opt/venv /opt/uv/python && chown 1000:1000 /opt/venv /opt/uv/python

# Python 3.14 is the newest version in CI. UV_LINK_MODE=copy avoids hardlink warnings
# between the uv cache and the venv.
ENV UV_PYTHON=3.14 \
    UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/opt/node/bin:$PATH \
    ORCA_SYNC_COMMAND="uv sync --extra test"
