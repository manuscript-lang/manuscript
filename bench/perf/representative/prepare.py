"""Deterministic whole-program workloads; reuse reference source and independent oracles."""
import argparse
import hashlib
import json
import pathlib
import random
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("output", type=pathlib.Path)
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
manifest = {}


def save(name, source, data, expected):
    folder = out / name
    folder.mkdir(exist_ok=True)
    (folder / "main.ms").write_text(source)
    (folder / "stdin").write_text(data)
    (folder / "expected").write_text(expected)
    manifest[name] = {p: hashlib.sha256((folder / p).read_bytes()).hexdigest()
                      for p in ("main.ms", "stdin", "expected")}


def reference(challenge, data):
    root = ROOT / "bench/agent/challenges" / challenge
    # Everything before the random generator is the oracle and its imports/constants.
    # Avoid running the generator's file-writing tail.
    scope = {}
    exec((root / "gen.py").read_text().split("rnd = random.Random(")[0], scope)
    save(challenge, (root / "solutions/ms/main.ms.ref").read_text(), data, scope["solve"](data))
    shutil.copy(root / "hidden/cases.json", out / challenge / "cases.json")
    shutil.copy(root / "solutions/rust/main.rs.ref", out / challenge / "main.rs")


rng = random.Random(241026)
lines = []
for i in range(200000):
    if i % 37 == 0:
        lines.append("malformed input")
    else:
        lines.append(f"2026-10-24T03:{i // 60 % 60:02d}:{i % 60:02d} "
                     f"{rng.choice(['DEBUG','INFO','WARN','ERROR'])} "
                     f"{rng.choice(['GET','POST','PUT','DELETE'])} "
                     f"/api/resource/{rng.randrange(300)} {rng.choice([200,201,301,404,503])} {rng.randrange(10000)}")
reference("c25-log-analyzer", "\n".join(lines) + "\n")

lines = [f"stock SKU-{i} 100000" for i in range(300)]
lines += [f"price SKU-{i} {17 + i * 11}" for i in range(300)]
for i in range(12000):
    items = " ".join(f"SKU-{k}:{rng.randrange(1,20)}" for k in rng.sample(range(300), 3))
    lines.append(f"order o{i} {items}")
    if i % 5 == 0:
        lines.append(f"cancel o{i}")
    elif i % 3 == 0:
        lines.append(f"ship o{i}")
    if i % 1000 == 0:
        lines.append("report")
lines.append("report")
reference("c13-inventory-orders", "\n".join(lines) + "\n")

lines = []
for i in range(200000):
    if i % 41 == 0:
        lines.append("invalid,row,ignored")
    elif i % 7 == 0:
        lines.append(f'"group,{i % 300}",{rng.randrange(10000)}.{rng.randrange(100):02d}')
    else:
        lines.append(f"group-{i % 300},{rng.randrange(10000)}.{rng.randrange(100):02d}")
reference("c03-csv-group-sum", "\n".join(lines) + "\n")

save("hello", 'import {stdout} from "@std/io.ms"\n\nexport fn main() Int:\n    if stdout().write("hello\\n").is_error():\n        return 1\n    return 0\n', "", "hello\n")
for n in [100, 200, 400, 1000, 2000, 4000]:
    source = 'import {stdin, stdout, read_line} from "@std/io.ms"\n\n'
    for i in range(n):
        source += f"fn rule_{i}(x: Int) Int:\n    return (x % 997) * 3 + {i}\n\n"
    source += 'export fn main() Int:\n    var x = read_line(stdin()).get().get().parse_int().get()\n'
    x = 17
    for i in range(n):
        source += f"    x = rule_{i}(x)\n"
        x = (x % 997) * 3 + i
    source += '    if stdout().write("{x}\\n").is_error():\n        return 1\n    return 0\n'
    save(f"rules-{n}", source, "17\n", f"{x}\n")
(out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest, indent=2))
