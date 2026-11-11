#!/usr/bin/env bash
# Shared helpers for the lima-ubuntu-lts environment recipe (see orca.yaml).
# Sourced by the lifecycle scripts in this directory. Adapted from the MIT-licensed
# "Lima VM Recipes for Orca" plugin (cemalkilic/lima-orca-vm-recipes).
#
# Stdout is reserved for the single JSON object Orca reads; diagnostics go to stderr.

# Remote that Orca's project identity points at (github:github/spec-kit). The fork's
# origin alone would not match the project, so the VM clone also gets this remote.
# shellcheck disable=SC2034 # read by lima-create.sh after sourcing
LIMA_UPSTREAM_DEFAULT_URL="https://github.com/github/spec-kit.git"

lima_fail() {
  echo "lima-recipe: $*" >&2
  exit 1
}

# Lima instance names come from Orca (orca-<uuid>). A destroy payload can carry the id,
# so refuse anything else before it reaches limactl.
lima_require_instance_name() {
  local name="$1"
  if [[ ! "$name" =~ ^orca-[A-Za-z0-9-]+$ ]]; then
    lima_fail "refusing instance name '$name': expected orca-<uuid> (letters, digits, hyphens)"
  fi
}

lima_instance_id_from_env() {
  local name="${ORCA_VM_INSTANCE_ID:-}"
  [ -n "$name" ] || lima_fail "ORCA_VM_INSTANCE_ID is not set"
  lima_require_instance_name "$name"
  printf '%s' "$name"
}

lima_json_escape() {
  printf '%s' "$1" | sed 's/[\\"]/\\&/g'
}

# Lima's own per-user key; it is authorized in every instance Lima creates.
lima_key_path() {
  printf '%s' "${LIMA_HOME:-$HOME/.lima}/_config/user"
}

# Prints the SSH connection Orca dials. Lima can pick a different port on restart,
# so resume prints it again.
lima_emit_connection() {
  local name="$1" root="$2" user port key
  user="$(limactl list "$name" --format '{{.Config.User.Name}}')"
  port="$(limactl list "$name" --format '{{.SSHLocalPort}}')"
  case "$port" in
    ""|0) lima_fail "Lima reported no SSH port for $name" ;;
  esac
  key="$(lima_key_path)"
  printf '{"schemaVersion":1,"connection":{"type":"ssh","projectRoot":"%s","target":{"label":"%s","host":"127.0.0.1","port":%s,"username":"%s","identityFile":"%s","identitiesOnly":true}}}\n' \
    "$(lima_json_escape "$root")" \
    "$(lima_json_escape "$name")" \
    "$port" \
    "$(lima_json_escape "$user")" \
    "$(lima_json_escape "$key")"
}
