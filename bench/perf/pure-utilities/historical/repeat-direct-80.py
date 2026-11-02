#!/usr/bin/env python3
"""POSIX/pure URL controls; exact fields/errors checked inside timing."""
import argparse
import hashlib
import itertools
import json
import os
import pathlib
import platform
import resource
import statistics
import subprocess
import time
import urllib.parse
ROOT = pathlib.Path(__file__).resolve().parents[3]

def path_parts(text):
    root = "/" if text.startswith("/") else ""
    trimmed = text.rstrip("/")
    base = trimmed.rsplit("/", 1)[-1]
    directory = trimmed.rsplit("/", 1)[0] if "/" in trimmed else root
    if len(directory) < len(root) or not base:
        directory = root
    at = base.rfind(".")
    ext = base[at:] if at > 0 and base not in (".", "..") else ""
    return [root, directory, base, ext, base[:-len(ext)] if ext else base]

def normalize(text):
    absolute = text.startswith("/")
    stack = []
    for part in text.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if stack and stack[-1] != "..":
                stack.pop()
            elif not absolute:
                stack.append(part)
        else:
            stack.append(part)
    out = ("/" if absolute else "") + "/".join(stack)
    out = out or "."
    return out + ("/" if text.endswith("/") and not out.endswith("/") else "")

def cases():
    rows = []
    def add(name, kind, op, text, fields=None, error=False):
        fields = (fields or []) + [""] * (6 - len(fields or []))
        status = "InvalidData" if error else "OK"
        # argv and plain TSV protocol restrictions, not utility input preconditions.
        for value in [text, *fields]:
            if len(value.encode()) > 8192 or "\0" in value:
                raise ValueError("case exceeds argv protocol bounds")
        if any("\t" in f or "\n" in f or "\r" in f for f in fields):
            raise ValueError("expected fields must fit plain TSV")
        rows.append(dict(case=name, kind=kind, op=op, input=text, status=status, fields=fields))
    paths = {
        "empty": "", "tiny": "a", "common": "/home/user/report.tar.gz",
        "unicode": "/資料/日付.é", "long-directory": "/" + "directory/" * 400 + "x.txt",
        "long-basename": "/a/" + "x" * 4096 + ".txt", "dotfile": "/a/.profile",
        "dotfile-extension": "/a/.config.json", "multiple-leading-dots": "...profile",
        "dot": ".", "dot-dot": "..", "trailing-slash": "/a/file.txt///",
        "root": "///", "repeated-slash": "//a///b.txt", "trailing-dot": "a.",
        "parent-dot": "../../a/./b/../c/", "above-root": "/../../a/../",
        "relative-empty-after-normalize": "a/../", "backslash-literal": "a\\b.txt",
        "long-no-extension": "/a/" + "x" * 4096,
        "long-dotfile": "/a/." + "x" * 4096,
        "long-many-dots": "/a/" + ".x" * 2000,
        "only-slashes": "/" * 4096,
        "many-parents": "a/../" * 512,
    }
    for name, text in paths.items():
        parts = path_parts(text)
        add("extension:" + name, "path", "extension", text, [parts[3]])
        add("parse:" + name, "path", "parse", text, parts)
        add("normalize:" + name, "path", "normalize", text, [normalize(text)])
    encodes = {"empty": "", "safe": "hello-._~AZ09", "common": "a b/c?x=1&y=2+z",
               "unicode": "é/資料 🕰", "long-safe": "a" * 4096,
               "long-escaped": "é" * 1000, "percent": "%25%zz"}
    for name, text in encodes.items():
        add("encode:" + name, "url", "encode", text, [urllib.parse.quote(text, safe="-._~")])
    decodes = {"empty": "", "safe": "hello-._~AZ09", "plus": "a+b%20c",
               "unicode": "%C3%A9%2F%E8%B3%87%E6%96%99", "mixed": "資料%2Fé+z",
               "long-safe": "a" * 4096, "long-percent": "%41" * 2000,
               "long-sparse": "a" * 2000 + "%20" + "b" * 2000,
               "long-tail-escape": "a" * 4000 + "%20",
               "long-head-escape": "%20" + "a" * 4000,
               "long-raw-unicode": "é" * 2000,
               "escaped-percent": "%252F"}
    for name, text in decodes.items():
        add("decode:" + name, "url", "decode", text,
            [urllib.parse.unquote_to_bytes(text).decode("utf-8", "strict")])
    # Predeclared controls around the conservative 256-byte search threshold.
    for size in [32, 64, 128, 255, 256, 257, 512]:
        for shape, text in {"safe": "a" * size,
                            "tail": "a" * (size - 3) + "%20",
                            "head": "%20" + "a" * (size - 3)}.items():
            add(f"decode:boundary-{shape}-{size}", "url", "decode", text,
                [urllib.parse.unquote_to_bytes(text).decode("utf-8", "strict")])
        add(f"decode-error:boundary-late-{size}", "url", "decode",
            "a" * (size - 3) + "%zz", error=True)
    for name, text in {"early-percent": "%zz" + "a" * 4000,
                       "late-percent": "a" * 4000 + "%zz", "short-percent": "%",
                       "one-digit": "%A", "bad-utf8": "%FF", "utf8-then-malformed": "%FF%zz", "overlong": "%C0%AF",
                       "surrogate": "%ED%A0%80", "above-unicode": "%F4%90%80%80",
                       "incomplete-utf8": "%E2%82", "late-utf8": "a" * 4000 + "%FF",
                       "valid-then-invalid": "%41" * 1000 + "%zz",
                       "valid-then-truncated": "%41" * 1000 + "%",
                       "unicode-then-invalid": "%C3%A9" * 500 + "%zz"}.items():
        add("decode-error:" + name, "url", "decode", text, error=True)
    valid_urls = [
        ("common", "HTTPS://Example.COM:8080/a%2Fb/c?x=1&y#frag", ["https", "example.com", "8080", "/a%2Fb/c", "x=1&y", "frag"]),
        ("tiny", "http://h", ["http", "h", "-1", "", "", ""]),
        ("ipv6", "http://[::1]:80/", ["http", "::1", "80", "/", "", ""]),
        ("hostless", "file:///etc/hosts", ["file", "", "-1", "/etc/hosts", "", ""]),
        ("fragment", "http://h/a#hello%20world", ["http", "h", "-1", "/a", "", "hello world"]),
        ("unicode", "http://h/é", ["http", "h", "-1", "/%C3%A9", "", ""]),
        ("long-path", "http://h/" + "a" * 4096, ["http", "h", "-1", "/" + "a" * 4096, "", ""]),
    ]
    for name, text, fields in valid_urls:
        add("url-parse:" + name, "url", "parse", text, fields)
    bad_urls = {"empty": "", "relative": "/relative", "opaque": "mailto:a@b",
                "userinfo": "http://u:p@host/", "port": "http://host:99999/",
                "host-colons": "http://host:80:80/", "host-space": "http://a b/",
                "query-space": "http://h/?q=a b", "early-control": "\x01http://h/" + "a" * 4000,
                "early-percent": "http://h/%zz" + "a" * 4000,
                "late-percent": "http://h/" + "a" * 4000 + "%zz",
                "late-utf8": "http://h/" + "a" * 4000 + "%FF"}
    for name, text in bad_urls.items():
        add("url-parse-error:" + name, "url", "parse", text, error=True)
    return rows

def sha(path):
    with pathlib.Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=["path", "url"], required=True)
    parser.add_argument("--producer", action="append", required=True,
                        help="label=/absolute/binary[::path-rust|path-native|url-rust|url-native]")
    parser.add_argument("--case", action="append")
    parser.add_argument("--count", type=int, default=200000)
    parser.add_argument("--repeats", type=int, default=24)
    parser.add_argument("--cpu", type=int, default=min(os.sched_getaffinity(0)))
    args = parser.parse_args()
    if args.count <= 0 or args.repeats <= 0:
        parser.error("count/repeats must be positive")
    selected = [c for c in cases() if c["kind"] == args.kind and (not args.case or c["case"] in args.case)]
    if not selected or (args.case and set(args.case) != {c["case"] for c in selected}):
        parser.error("unknown/empty case selection")
    producers = []
    for item in args.producer:
        label, spec = item.split("=", 1)
        path, *mode = spec.split("::")
        if mode and mode not in [[args.kind + "-rust"], [args.kind + "-native"]]:
            parser.error("mode does not match kind")
        producers.append((label, [str(pathlib.Path(path).resolve()), *mode]))
    if len(set(label for label, _ in producers)) != len(producers):
        parser.error("duplicate producer labels")
    if len(producers) > 4:
        parser.error("use at most four producers")
    orders = list(itertools.permutations(producers))
    if args.repeats % len(orders):
        parser.error("use at most four producers and repeats divisible by producer permutations")
    os.sched_setaffinity(0, {args.cpu})
    sources = ["crates/ms-std-path/src/lib.rs", "crates/ms-std-url/src/lib.rs", "crates/ms-std-url/src/gourl.rs",
               "stdlib/fs.ms", "stdlib/net.ms", "rust-toolchain.toml", "scripts/lld.lock", "Cargo.lock"]
    sources += ["bench/perf/pure-utilities/" + p for p in ["path.ms", "url.ms", "repeat.py", "rust/src/main.rs", "rust/Cargo.toml"]]
    if (ROOT / "bench/perf/pure-utilities/rust/Cargo.lock").is_file():
        sources.append("bench/perf/pure-utilities/rust/Cargo.lock")
    print(json.dumps({"kind": "environment", "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                      "source_sha256": {p: sha(ROOT / p) for p in sources},
                      "rustc": subprocess.check_output(["rustc", "--version"], text=True).strip(),
                      "cargo": subprocess.check_output(["cargo", "--version"], text=True).strip(),
                      "machine": {k: v for k, v in platform.uname()._asdict().items() if k != "node"},
                      "selectors": {k: os.environ.get(k) for k in ["MS_BACKEND", "MS_LLVM_TOOLS"]},
                      "utility_kind": args.kind, "cases": selected, "order_protocol": "all producer permutations"}), flush=True)
    for label, command in producers:
        print(json.dumps({"kind": "identity", "label": label, "path": command[0], "mode": command[1:],
                          "sha256": sha(command[0]), "cpu": args.cpu}), flush=True)
    rows = []
    for trial in range(-1, args.repeats):
        rotation = max(trial, 0) % len(selected)
        for case in selected[rotation:] + selected[:rotation]:
            count = max(2, args.count // max(1, len(case["input"].encode()) // 32))
            order = orders[(trial + 1) % len(orders)]
            for position, (label, command) in enumerate(order):
                started = time.monotonic_ns()
                before = resource.getrusage(resource.RUSAGE_CHILDREN)
                result = subprocess.run(command + [str(count), case["op"], case["input"], case["status"], *case["fields"]],
                                        check=True, capture_output=True, text=True, timeout=60)
                after = resource.getrusage(resource.RUSAGE_CHILDREN)
                if result.stderr:
                    raise ValueError(result.stderr)
                parts = result.stdout.removesuffix("\n").split("\t")
                if len(parts) != 10:
                    raise ValueError(result.stdout)
                found, ns, checksum = map(int, parts[:3])
                expected_sum = sum(len(f.encode()) for f in case["fields"]) + (case["status"] == "InvalidData")
                if found != count or not 0 < ns < time.monotonic_ns() - started or checksum != expected_sum * count or parts[3:] != [case["status"], *case["fields"]]:
                    raise ValueError(result.stdout)
                row = {"kind": "sample", "trial": trial, "case": case["case"], "label": label,
                       "position": position, "count": count, "ns": ns, "checksum": checksum,
                       "status": parts[3], "fields": parts[4:],
                       "process_cpu_seconds": after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime}
                print(json.dumps(row), flush=True)
                if trial >= 0:
                    rows.append(row)
    for case in selected:
        for label, _ in producers:
            samples = [r["ns"] / r["count"] for r in rows if r["case"] == case["case"] and r["label"] == label]
            if len(samples) != args.repeats:
                raise ValueError("missing/duplicate samples")
            print(json.dumps({"kind": "summary", "case": case["case"], "label": label,
                              "median_ns": statistics.median(samples), "min_ns": min(samples), "max_ns": max(samples)}), flush=True)

if __name__ == "__main__":
    main()
