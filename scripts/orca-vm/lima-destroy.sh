#!/usr/bin/env bash
# Orca "destroy" step for the lima-ubuntu-lts recipe. Deletes the VM; safe to retry.
# The instance id comes from ORCA_VM_INSTANCE_ID, or from the lifecycle JSON on stdin
# when Orca cannot set it (a create that never returned a result).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lima-lib.sh
. "$here/lima-lib.sh"

if [ -n "${ORCA_VM_INSTANCE_ID:-}" ]; then
  name="$ORCA_VM_INSTANCE_ID"
else
  payload="$(cat)"
  name="$(printf '%s' "$payload" | sed -n 's/.*"instanceId":"\([^"]*\)".*/\1/p' | head -n 1)"
  [ -n "$name" ] || lima_fail "no instance id in ORCA_VM_INSTANCE_ID or the stdin payload"
fi
lima_require_instance_name "$name"

limactl delete --force "$name" >&2
