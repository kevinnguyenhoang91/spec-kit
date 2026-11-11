#!/usr/bin/env bash
# Orca "create" step for the lima-ubuntu-lts recipe. Boots one disposable Lima VM for
# the workspace, copies the repo in as a git bundle, and prints the SSH connection.
# Runs from the repo root. Stdout carries only the recipe-result JSON.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lima-lib.sh
. "$here/lima-lib.sh"

name="$(lima_instance_id_from_env)"

# Check the host repo before booting anything, so an unmatched repo costs no VM.
remotes="$(git remote)"
if [ -z "$remotes" ]; then
  lima_fail "the repo has no Git remote. Orca links the VM checkout to the project by its remotes; add one (git remote add origin <url>)."
fi

top="$(git rev-parse --show-toplevel)"
root_name="$(basename "$top")"
upstream_url="${LIMA_UPSTREAM_URL:-$LIMA_UPSTREAM_DEFAULT_URL}"

bundle="$(mktemp "${TMPDIR:-/tmp}/orca-lima.XXXXXX")"
ok=""
cleanup() {
  rm -f "$bundle"
  # A failed or interrupted create must not leave a VM running.
  if [ -z "$ok" ]; then
    limactl delete --force "$name" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 1' INT TERM

# No host mounts: agents in the VM must not see the host's home directory.
limactl start --tty=false --name "$name" --mount-none --containerd none \
  --cpus 2 --memory 4 --disk 20 template:ubuntu-lts >&2
home="$(limactl list "$name" --format '{{.Config.User.Home}}')"

# A bundle of the local branches works for private repos without credentials in the VM.
(cd "$top" && git bundle create "$bundle" --branches HEAD) >&2
limactl copy "$bundle" "$name:$home/repo.bundle" >&2
root="$home/$root_name"
limactl shell --workdir / "$name" -- git clone -q "$home/repo.bundle" "$root" >&2
limactl shell --workdir / "$name" -- rm -f "$home/repo.bundle" >&2

# Orca links the VM checkout to the project by its remotes, so mirror the host's
# remotes; the bundle clone's origin would point at the deleted bundle. Credentials
# embedded in http(s) URLs are stripped so host tokens never reach the VM.
limactl shell --workdir / "$name" -- git -C "$root" remote remove origin >&2
while IFS= read -r remote; do
  url="$(git -C "$top" remote get-url "$remote" | sed -E 's#^(https?://)[^/@]*@#\1#')"
  limactl shell --workdir / "$name" -- git -C "$root" remote add "$remote" "$url" </dev/null >&2
done <<< "$remotes"

# This repo is a fork of github/spec-kit, and Orca's project identity is the upstream.
# Without an upstream remote the VM checkout identifies as the fork and is rejected.
if ! grep -qx 'upstream' <<< "$remotes"; then
  limactl shell --workdir / "$name" -- git -C "$root" remote add upstream "$upstream_url" </dev/null >&2
fi

lima_emit_connection "$name" "$root"
ok=1
