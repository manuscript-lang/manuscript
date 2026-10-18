#!/usr/bin/env python3
"""Black-box ms lsp review harness. No third-party Python dependencies."""
import argparse
import hashlib
import json
import math
import os
import pathlib
import platform
import queue
import statistics
import subprocess
import threading
import time


def fixture(base, name, modules, functions):
    root = base / name
    src = root / "src"
    src.mkdir(parents=True, exist_ok=True)
    (root / "ms.toml").write_text('[project]\nname = "perf_review"\nsource = "./src"\nentry = "./src/main.ms"\n')
    imports = []
    for m in range(modules):
        imports.append(f'import f_{m}_0 from "./part_{m}.ms"')
        text = f'# deterministic module {m}; Unicode 😀 é\n'
        text += '\n'.join(f'export fn f_{m}_{f}(value: Int) Int:\n    return value + {f}\n' for f in range(functions))
        (src / f"part_{m}.ms").write_text(text)
    text = '\n'.join(imports) + '\n\nexport fn main() Int:\n    let result = f_0_0(1)\n    return result\n'
    (src / "main.ms").write_text(text)
    files = [src / "main.ms"] + [src / f"part_{m}.ms" for m in range(modules)]
    return root, files


class Session:
    def __init__(self, binary, root):
        self.q = queue.Queue()
        self.seq = 0
        self.notifications = []
        self.responses = {}
        self.started = time.perf_counter_ns()
        self.p = subprocess.Popen([str(binary), "lsp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  cwd=root, env={**os.environ, "GOMAXPROCS": "4"})
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def read(self):
        try:
            while True:
                length = None
                while True:
                    line = self.p.stdout.readline()
                    if not line:
                        raise EOFError("server stdout closed")
                    if line == b"\r\n":
                        break
                    if line.lower().startswith(b"content-length:"):
                        length = int(line.split(b":", 1)[1])
                payload = self.p.stdout.read(length)
                self.q.put((time.perf_counter_ns(), json.loads(payload), len(payload)))
        except Exception as e:
            self.q.put((time.perf_counter_ns(), {"reader_error": repr(e)}, 0))

    def send(self, method, params=None, request=False):
        msg = {"jsonrpc": "2.0", "method": method, "params": params or {}}
        if request:
            self.seq += 1
            msg["id"] = self.seq
        body = json.dumps(msg, separators=(",", ":"), ensure_ascii=False).encode()
        at = time.perf_counter_ns()
        self.p.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
        self.p.stdin.flush()
        return msg.get("id"), at

    def receive(self, ident):
        while ident not in self.responses:
            at, msg, size = self.q.get(timeout=180)
            if "reader_error" in msg:
                raise RuntimeError(msg)
            if "id" in msg:
                self.responses[msg["id"]] = (at, msg, size)
            else:
                self.notifications.append((at, msg, size))
        return self.responses.pop(ident)

    def request(self, method, params=None):
        ident, sent = self.send(method, params, True)
        at, msg, size = self.receive(ident)
        if "error" in msg:
            raise RuntimeError(msg)
        return (at - sent) / 1e6, msg.get("result"), size

    def initialize(self, root):
        return self.request("initialize", {"processId": os.getpid(), "rootUri": root.as_uri(),
                            "capabilities": {"textDocument": {"completion": {"completionItem": {"snippetSupport": True}}}}})

    def open(self, file, version=1):
        uri = file.as_uri()
        _, sent = self.send("textDocument/didOpen", {"textDocument": {"uri": uri, "languageId": "manuscript", "version": version, "text": file.read_text()}})
        self.request("textDocument/documentSymbol", {"textDocument": {"uri": uri}})
        notices = self.notifications
        self.notifications = []
        own = [x for x in notices if x[1].get("params", {}).get("uri") == uri]
        assert own, notices
        errors = [d for x in notices for d in x[1].get("params", {}).get("diagnostics", []) if d["severity"] == 1]
        assert not errors, errors
        return (own[-1][0] - sent) / 1e6, notices

    def memory(self):
        result = {}
        for line in pathlib.Path(f"/proc/{self.p.pid}/status").read_text().splitlines():
            if line.startswith(("VmRSS:", "VmHWM:", "Threads:")):
                key, value = line.split(":", 1)
                result[key] = value.strip()
        return result

    def close(self):
        try:
            self.request("shutdown")
            self.send("exit")
            self.p.wait(timeout=5)
        finally:
            if self.p.poll() is None:
                self.p.kill()
            self.p.stdin.close()
            self.p.stdout.close()
            self.p.stderr.close()


def summary(samples):
    times = sorted(x["ms"] for x in samples)
    return {"n": len(times), "p50_ms": statistics.median(times), "p95_ms": times[math.ceil(.95 * len(times)) - 1] if len(times) >= 20 else None,
            "min_ms": min(times), "max_ms": max(times)}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--repo", type=pathlib.Path, required=True)
    p.add_argument("--out", type=pathlib.Path, required=True)
    p.add_argument("--sizes", default="small:2:10,large:40:20")
    p.add_argument("--samples", type=int, default=20)
    p.add_argument("--cold", type=int, default=7)
    p.add_argument("--allow-coalescing", action="store_true")
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    raw = []
    groups = {}
    metadata = {"revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=args.repo, text=True).strip(),
                "binary_sha256": hashlib.sha256((args.repo / "ms").read_bytes()).hexdigest(),
                "tracked_diff_sha256": hashlib.sha256(subprocess.check_output(["git", "diff", "HEAD"], cwd=args.repo)).hexdigest(),
                "platform": platform.platform(), "python": platform.python_version(), "gomaxprocs": 4,
                "clock": "perf_counter_ns; elapsed from frame write to reader receipt", "cold_definition": "fresh process; OS page cache uncontrolled/warm",
                "warm_definition": "one session; initialized and documents opened; includes first lazy derived-cache miss; requests in source order",
                "fixtures": {}}
    def record(group, ms, **extra):
        item = {"group": group, "ms": ms, **extra}
        raw.append(item)
        groups.setdefault(group, []).append(item)
        with (args.out / "raw.jsonl").open("a") as f:
            f.write(json.dumps(item) + "\n")
    (args.out / "raw.jsonl").write_text("")
    for spec in args.sizes.split(","):
        name, modules, functions = spec.split(":")
        root, files = fixture(args.out / "fixtures", name, int(modules), int(functions))
        metadata["fixtures"][name] = {"modules_including_main": len(files), "functions_per_module": int(functions), "source_bytes": sum(f.stat().st_size for f in files)}
        print("fixture", name, metadata["fixtures"][name], flush=True)
        for sample in range(args.cold):
            s = Session(args.repo / "ms", root)
            try:
                ms, _, size = s.initialize(root)
                record(name + "/initialize_fresh_process", (time.perf_counter_ns() - s.started) / 1e6, response_bytes=size)
                ms, notices = s.open(files[0])
                record(name + "/first_open_fresh_process", ms, notifications=len(notices), memory=s.memory())
            finally:
                s.close()
        for tabs in [1, min(10, len(files))]:
            s = Session(args.repo / "ms", root)
            try:
                s.initialize(root)
                for f in files[:tabs]:
                    s.open(f)
                uri = files[0].as_uri()
                source = files[0].read_text()
                line = source[:source.index("f_0_0(1)")].count("\n")
                params = {"textDocument": {"uri": uri}, "position": {"line": line, "character": 20}}
                prefix = f"{name}/tabs{tabs}"
                for i in range(args.samples):
                    ident, sent = s.send("review/noop", {}, True)
                    at, result, size = s.receive(ident)
                    assert result["error"]["code"] == -32601
                    record(prefix + "/warm_transport_error_baseline", (at - sent) / 1e6, response_bytes=size)
                for method in ["hover", "definition", "completion", "signatureHelp", "semanticTokens/full", "documentSymbol"]:
                    for i in range(args.samples):
                        ms, result, size = s.request("textDocument/" + method, {**params, "position": {"line": line, "character": 24}} if method == "signatureHelp" else params)
                        assert result is not None, (method, result)
                        if method == "completion":
                            assert any(x["label"] == "f_0_0" for x in result), result
                        if method == "definition":
                            assert len(result) == 1 and result[0]["uri"].endswith("part_0.ms"), result
                        if method == "semanticTokens/full":
                            assert result["data"] and len(result["data"]) % 5 == 0, result
                        normalized = json.dumps(result, sort_keys=True).replace(root.as_uri(), "fixture://" + name)
                        digest = hashlib.sha256(normalized.encode()).hexdigest()
                        record(prefix + "/warm_" + method, ms, response_bytes=size,
                               result_items=len(result) if isinstance(result, list) else None, result_sha256=digest)
                version = 1
                for i in range(args.samples):
                    version += 1
                    _, sent = s.send("textDocument/didChange", {"textDocument": {"uri": uri, "version": version}, "contentChanges": [{"range": {"start": {"line": line, "character": 23}, "end": {"line": line, "character": 24}}, "text": str(1 + i % 2)}]})
                    s.request("textDocument/documentSymbol", {"textDocument": {"uri": uri}})
                    notices = s.notifications
                    s.notifications = []
                    assert len(notices) == tabs, (tabs, len(notices))
                    own = [x for x in notices if x[1]["params"]["uri"] == uri]
                    assert own[-1][1]["params"]["version"] == version
                    assert not [d for x in notices for d in x[1]["params"]["diagnostics"] if d["severity"] == 1], notices
                    record(prefix + "/edit_to_own_diagnostics", (own[-1][0] - sent) / 1e6)
                    record(prefix + "/edit_to_all_diagnostics", (notices[-1][0] - sent) / 1e6, notifications=len(notices))
                for i in range(3):
                    start = time.perf_counter_ns()
                    for j in range(10):
                        version += 1
                        s.send("textDocument/didChange", {"textDocument": {"uri": uri, "version": version}, "contentChanges": [{"range": {"start": {"line": line, "character": 23}, "end": {"line": line, "character": 24}}, "text": str(1 + j % 2)}]})
                    s.request("textDocument/documentSymbol", {"textDocument": {"uri": uri}})
                    notices = s.notifications
                    s.notifications = []
                    if args.allow_coalescing:
                        assert 0 < len(notices) <= tabs * 10 and len(notices) % tabs == 0, len(notices)
                    else:
                        assert len(notices) == tabs * 10, len(notices)
                    own = [x for x in notices if x[1]["params"]["uri"] == uri]
                    assert own[-1][1]["params"]["version"] == version, own
                    assert not [d for x in notices for d in x[1]["params"]["diagnostics"] if d["severity"] == 1], notices
                    record(prefix + "/burst10_to_all_diagnostics", (notices[-1][0] - start) / 1e6, notifications=len(notices), versions=sorted({x[1]["params"]["version"] for x in notices if x[1]["params"]["uri"] == uri}))
                for method, prm in [("textDocument/references", {**params, "context": {"includeDeclaration": True}}), ("workspace/symbol", {"query": "f_0_0"})]:
                    for i in range(3):
                        ms, result, size = s.request(method, prm)
                        assert result, (method, result)
                        record(prefix + "/warm_" + method, ms, response_bytes=size, result_items=len(result))
                ident, sent = s.send("workspace/symbol", {"query": "f_0_0"}, True)
                s.send("$/cancelRequest", {"id": ident})
                follow, follow_sent = s.send("textDocument/hover", params, True)
                at, canceled, _ = s.receive(ident)
                follow_at, _, _ = s.receive(follow)
                record(prefix + "/canceled_workspace_symbol", (at - sent) / 1e6, response=canceled)
                record(prefix + "/hover_queued_after_cancel", (follow_at - follow_sent) / 1e6)
                for i in range(3):
                    _, sent = s.send("workspace/didChangeWatchedFiles", {"changes": [{"uri": (root / "unrelated.toml").as_uri(), "type": 2}]})
                    s.request("textDocument/documentSymbol", {"textDocument": {"uri": uri}})
                    notices = s.notifications
                    s.notifications = []
                    if args.allow_coalescing:
                        assert not notices, notices
                        record(prefix + "/unrelated_watched_toml_barrier", (time.perf_counter_ns() - sent) / 1e6, notifications=0)
                    else:
                        record(prefix + "/unrelated_watched_toml", (notices[-1][0] - sent) / 1e6, notifications=len(notices))
                metadata.setdefault("memory_after", {})[prefix] = s.memory()
            finally:
                s.close()
            print("completed", prefix, flush=True)
    (args.out / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    result = {key: summary(samples) for key, samples in groups.items()}
    (args.out / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
    for key, value in result.items():
        print(key, json.dumps(value), flush=True)


if __name__ == "__main__":
    main()
