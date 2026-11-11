#!/usr/bin/env bash
# scripts.setup for spec-kit (orca.yaml). Installs the Python dependencies with uv.
# The Ubuntu base image has no uv, so it is installed here when missing.
set -euo pipefail

UV_VERSION="0.9.22"
export PATH="$HOME/.local/bin:$PATH"

if ! command -v uv >/dev/null 2>&1; then
  echo "setup: uv not found; installing uv $UV_VERSION" >&2
  curl --proto '=https' --tlsv1.2 -LsSf "https://astral.sh/uv/$UV_VERSION/install.sh" | sh >&2
fi

uv sync --extra test
