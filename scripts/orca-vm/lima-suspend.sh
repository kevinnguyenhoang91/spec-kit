#!/usr/bin/env bash
# Orca "suspend" step for the lima-ubuntu-lts recipe. Lima has no pause: stopping keeps
# the disk and frees CPU and memory.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lima-lib.sh
. "$here/lima-lib.sh"

name="$(lima_instance_id_from_env)"
limactl stop "$name" >&2
