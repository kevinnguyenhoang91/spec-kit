# Base image for Orca workspace containers. Toolchain and system packages only:
# the Orca plugin adds sshd, the dev user (uid 1000), agent CLIs and Podman,
# copies the repo to /home/dev/spec-kit and runs ORCA_SYNC_COMMAND there as dev.
FROM ubuntu:24.04

# git: the test suite runs git in many tests. ca-certificates: uv downloads Python over HTTPS.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

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
    PATH=/opt/venv/bin:$PATH \
    ORCA_SYNC_COMMAND="uv sync --extra test"
