"""Behavior tests for the lima-ubuntu-lts Orca recipe scripts (scripts/orca-vm/).

The scripts drive Lima, so these tests put a stub ``limactl`` first on PATH that
records its arguments. Each test runs the real script in a temporary git repo.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = REPO_ROOT / "scripts" / "orca-vm"
INSTANCE = "orca-test-1"
VM_HOME = "/home/tester"
VM_PORT = "55555"
FORK = "https://example.com/fork/spec-kit.git"

pytestmark = pytest.mark.skipif(
    os.name == "nt" or shutil.which("bash") is None or shutil.which("git") is None,
    reason="Lima recipe scripts are POSIX bash and need git",
)

FAKE_LIMACTL = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAKE_LIMACTL_LOG"
case "$1" in
  start)
    [ -z "${FAKE_LIMACTL_FAIL_START:-}" ] || exit 1
    ;;
  list)
    case "$*" in
      *Config.User.Home*) echo "__HOME__" ;;
      *Config.User.Name*) echo "tester" ;;
      *SSHLocalPort*) echo "__PORT__" ;;
    esac
    ;;
esac
exit 0
""".replace("__HOME__", VM_HOME).replace("__PORT__", VM_PORT)


@pytest.fixture
def fake_env(tmp_path: Path) -> dict[str, str]:
    bindir = tmp_path / "bin"
    bindir.mkdir()
    limactl = bindir / "limactl"
    limactl.write_text(FAKE_LIMACTL, encoding="utf-8")
    limactl.chmod(0o755)
    env = dict(os.environ)
    env.pop("ORCA_VM_INSTANCE_ID", None)
    env.pop("FAKE_LIMACTL_FAIL_START", None)
    env.update(
        PATH=f"{bindir}{os.pathsep}{os.environ.get('PATH', '')}",
        FAKE_LIMACTL_LOG=str(tmp_path / "limactl.log"),
        GIT_CONFIG_GLOBAL=os.devnull,
        GIT_AUTHOR_NAME="t",
        GIT_AUTHOR_EMAIL="t@example.com",
        GIT_COMMITTER_NAME="t",
        GIT_COMMITTER_EMAIL="t@example.com",
    )
    return env


def make_repo(tmp_path: Path, remotes: dict[str, str]) -> Path:
    repo = tmp_path / "spec-kit"
    repo.mkdir()
    git = ["git", "-c", "commit.gpgsign=false", "-C", str(repo)]
    subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
    (repo / "README.md").write_text("x\n", encoding="utf-8")
    subprocess.run([*git, "add", "README.md"], check=True)
    subprocess.run([*git, "commit", "-q", "-m", "init"], check=True)
    for name, url in remotes.items():
        subprocess.run([*git, "remote", "add", name, url], check=True)
    return repo


def run_script(
    script: str,
    cwd: Path,
    env: dict[str, str],
    stdin: str = "",
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPTS / script)],
        cwd=cwd,
        env=env,
        input=stdin,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )


def limactl_log(env: dict[str, str]) -> list[str]:
    path = Path(env["FAKE_LIMACTL_LOG"])
    return path.read_text(encoding="utf-8").splitlines() if path.exists() else []


def with_instance(env: dict[str, str]) -> dict[str, str]:
    return {**env, "ORCA_VM_INSTANCE_ID": INSTANCE}


# --- create -----------------------------------------------------------------


def test_create_prints_ssh_connection_and_mirrors_remotes(tmp_path, fake_env):
    repo = make_repo(tmp_path, {"origin": FORK})
    result = run_script("lima-create.sh", repo, with_instance(fake_env))

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    connection = payload["connection"]
    assert payload["schemaVersion"] == 1
    assert connection["type"] == "ssh"
    assert connection["projectRoot"] == f"{VM_HOME}/spec-kit"
    assert connection["target"]["port"] == int(VM_PORT)
    assert connection["target"]["host"] == "127.0.0.1"

    log = limactl_log(fake_env)
    assert any(line.endswith(f"remote add origin {FORK}") for line in log)
    # The fork's identity would be rejected, so the VM also gets the project upstream.
    assert any(
        "remote add upstream https://github.com/github/spec-kit.git" in line
        for line in log
    )
    assert not any(line.startswith("delete") for line in log)


def test_create_keeps_existing_upstream_remote(tmp_path, fake_env):
    repo = make_repo(
        tmp_path,
        {"origin": FORK, "upstream": "https://example.com/other/spec-kit.git"},
    )
    result = run_script("lima-create.sh", repo, with_instance(fake_env))

    assert result.returncode == 0, result.stderr
    log = limactl_log(fake_env)
    assert not any(
        "remote add upstream https://github.com/github/spec-kit.git" in line
        for line in log
    )
    assert any(
        "remote add upstream https://example.com/other/spec-kit.git" in line
        for line in log
    )


def test_create_refuses_repo_without_remote_before_booting(tmp_path, fake_env):
    repo = make_repo(tmp_path, {})
    result = run_script("lima-create.sh", repo, with_instance(fake_env))

    assert result.returncode != 0
    assert "no Git remote" in result.stderr
    assert not any(line.startswith("start") for line in limactl_log(fake_env))


def test_create_requires_instance_id(tmp_path, fake_env):
    repo = make_repo(tmp_path, {"origin": FORK})
    result = run_script("lima-create.sh", repo, fake_env)

    assert result.returncode != 0
    assert "ORCA_VM_INSTANCE_ID is not set" in result.stderr
    assert limactl_log(fake_env) == []


def test_create_rejects_unsafe_instance_name(tmp_path, fake_env):
    repo = make_repo(tmp_path, {"origin": FORK})
    env = {**fake_env, "ORCA_VM_INSTANCE_ID": "orca-x;rm -rf ~"}
    result = run_script("lima-create.sh", repo, env)

    assert result.returncode != 0
    assert "refusing instance name" in result.stderr
    assert limactl_log(fake_env) == []


def test_create_deletes_vm_when_boot_fails(tmp_path, fake_env):
    repo = make_repo(tmp_path, {"origin": FORK})
    env = {**with_instance(fake_env), "FAKE_LIMACTL_FAIL_START": "1"}
    result = run_script("lima-create.sh", repo, env)

    assert result.returncode != 0
    assert f"delete --force {INSTANCE}" in limactl_log(fake_env)


# --- destroy ----------------------------------------------------------------


def test_destroy_deletes_instance_from_env(tmp_path, fake_env):
    result = run_script("lima-destroy.sh", tmp_path, with_instance(fake_env))

    assert result.returncode == 0, result.stderr
    assert f"delete --force {INSTANCE}" in limactl_log(fake_env)


def test_destroy_reads_instance_from_stdin_payload(tmp_path, fake_env):
    result = run_script(
        "lima-destroy.sh", tmp_path, fake_env, stdin='{"instanceId":"orca-abc-123"}'
    )

    assert result.returncode == 0, result.stderr
    assert "delete --force orca-abc-123" in limactl_log(fake_env)


def test_destroy_rejects_unsafe_payload_instance(tmp_path, fake_env):
    result = run_script(
        "lima-destroy.sh", tmp_path, fake_env, stdin='{"instanceId":"orca-a;b"}'
    )

    assert result.returncode != 0
    assert "refusing instance name" in result.stderr
    assert limactl_log(fake_env) == []


def test_destroy_without_any_id_fails(tmp_path, fake_env):
    result = run_script("lima-destroy.sh", tmp_path, fake_env, stdin="{}")

    assert result.returncode != 0
    assert "no instance id" in result.stderr
    assert limactl_log(fake_env) == []


# --- suspend and resume -----------------------------------------------------


def test_suspend_stops_instance(tmp_path, fake_env):
    result = run_script("lima-suspend.sh", tmp_path, with_instance(fake_env))

    assert result.returncode == 0, result.stderr
    assert f"stop {INSTANCE}" in limactl_log(fake_env)


def test_resume_starts_instance_and_reprints_connection(tmp_path, fake_env):
    repo = make_repo(tmp_path, {"origin": FORK})
    result = run_script("lima-resume.sh", repo, with_instance(fake_env))

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["connection"]["projectRoot"] == f"{VM_HOME}/spec-kit"
    assert payload["connection"]["target"]["port"] == int(VM_PORT)
    assert any(
        line.startswith(f"start --tty=false {INSTANCE}")
        for line in limactl_log(fake_env)
    )
