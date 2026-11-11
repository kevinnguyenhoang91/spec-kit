#!/usr/bin/env bash
# Orca "resume" step for the lima-ubuntu-lts recipe. Starts the stopped VM and prints
# the SSH connection again, because Lima may pick a new port. Runs from the repo root.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lima-lib.sh
. "$here/lima-lib.sh"

name="$(lima_instance_id_from_env)"
root_name="$(basename "$(git rev-parse --show-toplevel)")"

limactl start --tty=false "$name" >&2
home="$(limactl list "$name" --format '{{.Config.User.Home}}')"
lima_emit_connection "$name" "$home/$root_name"
