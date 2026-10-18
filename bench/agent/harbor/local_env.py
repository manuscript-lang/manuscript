"""Harbor environment that runs trials as plain processes on the host (no container runtime).

For development where Docker is unavailable. NOT a sandbox: the agent can read the whole host
filesystem, including hidden tests. Use Docker or a remote sandbox for real baseline runs.

Task paths such as /app, /tests, /solution and /logs/* are provided inside each command's private
mount namespace (`unshare -m`), so concurrent trials do not collide. Requires root (or a user that
may create mount namespaces) on Linux. Because the task's Dockerfile is not built, the toolchains
(node, go, cargo, ms, python3) must already be on the host PATH.

Convention: files under `environment/workspace/` are copied into /app on start, standing in for the
Dockerfile's `COPY workspace /app`.

    PYTHONPATH=bench/agent/harbor harbor run -p <task-dir> -a claude-code -m <model> \\
        --env local_env:LocalProcessEnvironment
"""
from __future__ import annotations

import asyncio
import os
import shutil
import signal
import tempfile
from pathlib import Path

from harbor.environments.base import BaseEnvironment, ExecResult
from harbor.environments.capabilities import EnvironmentCapabilities

# Container paths that always get a private host directory, in addition to mounts Harbor supplies.
ALWAYS_MAPPED = ("/app", "/tests", "/solution", "/logs/agent", "/logs/verifier", "/logs/artifacts")


class LocalProcessEnvironment(BaseEnvironment):
    @staticmethod
    def type() -> str:
        return "local-process"

    @property
    def capabilities(self) -> EnvironmentCapabilities:
        return EnvironmentCapabilities(mounted=True)

    def _validate_definition(self):
        if not shutil.which("unshare"):
            raise FileNotFoundError("local-process environment needs `unshare` (Linux, util-linux)")

    # -- path mapping ------------------------------------------------------------------------
    def _host_path(self, path: str) -> Path:
        best = None
        for target, src in self._binds.items():
            if path == target or path.startswith(target.rstrip("/") + "/"):
                if best is None or len(target) > len(best[0]):
                    best = (target, src)
        if best is None:
            return Path(path)
        return Path(best[1]) / path[len(best[0]):].lstrip("/")

    async def start(self, force_build: bool) -> None:
        self._root = Path(tempfile.mkdtemp(prefix="agent-bench-local-"))
        self._binds: dict[str, str] = {}
        for m in self._mounts:
            if m.get("type") == "bind":
                self._binds[m["target"]] = m["source"]
        for target in ALWAYS_MAPPED:
            if target not in self._binds and not any(t != target and target.startswith(t + "/") for t in self._binds):
                d = self._root / target.strip("/")
                d.mkdir(parents=True, exist_ok=True)
                self._binds[target] = str(d)
        for target in self._binds:
            os.makedirs(target, exist_ok=True)  # mountpoints on the host
        ws = Path(self.environment_dir) / "workspace"
        if ws.is_dir():
            shutil.copytree(ws, self._host_path("/app"), dirs_exist_ok=True)

    async def stop(self, delete: bool):
        if delete and getattr(self, "_root", None):
            shutil.rmtree(self._root, ignore_errors=True)

    # -- file transfer -----------------------------------------------------------------------
    async def upload_file(self, source_path, target_path: str):
        dst = self._host_path(target_path)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, dst)

    async def upload_dir(self, source_dir, target_dir: str):
        shutil.copytree(source_dir, self._host_path(target_dir), dirs_exist_ok=True)

    async def download_file(self, source_path: str, target_path):
        Path(target_path).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(self._host_path(source_path), target_path)

    async def download_dir(self, source_dir: str, target_dir):
        shutil.copytree(self._host_path(source_dir), target_dir, dirs_exist_ok=True)

    # -- exec --------------------------------------------------------------------------------
    async def exec(self, command, cwd=None, env=None, timeout_sec=None, user=None) -> ExecResult:
        binds = "\n".join(f"mount --bind '{src}' '{t}'" for t, src in self._binds.items())
        wrapper = f"set -e\n{binds}\ncd '{cwd or '/app'}'\nset +e\nexec bash -c \"$MSBENCH_CMD\"\n"
        full_env = {**os.environ, **(self._merge_env(env) or {})}
        full_env["MSBENCH_CMD"] = command
        proc = await asyncio.create_subprocess_exec(
            "unshare", "-m", "--propagation", "private", "bash", "-c", wrapper,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
            env=full_env, start_new_session=True,
        )
        try:
            out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout_sec)
        except asyncio.TimeoutError:
            os.killpg(proc.pid, signal.SIGKILL)
            out, err = await proc.communicate()
            return ExecResult(stdout=out.decode(errors="replace"), stderr="timeout", return_code=124)
        return ExecResult(stdout=out.decode(errors="replace"), stderr=err.decode(errors="replace"),
                          return_code=proc.returncode)
