import json, random, re, pathlib

INT = r"-?[0-9]{1,10}"

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    mode = lines[0] if lines else ""
    m = re.fullmatch(rf"merge|total|gaps ({INT}) ({INT})", mode)
    lo = hi = 0
    if m and mode.startswith("gaps"):
        lo, hi = int(m.group(1)), int(m.group(2))
        if lo > hi: m = None
    if not m: return "error: bad mode\n"
    ivs = []
    for i, l in enumerate(lines[1:], 2):
        if l.strip(" ") == "": continue
        t = re.fullmatch(rf"({INT}) ({INT})", l)
        if not t or int(t.group(1)) > int(t.group(2)): return f"error: line {i}\n"
        ivs.append((int(t.group(1)), int(t.group(2))))
    ivs.sort()
    merged = []
    for a, b in ivs:
        if merged and a <= merged[-1][1] + 1: merged[-1][1] = max(merged[-1][1], b)
        else: merged.append([a, b])
    if mode == "merge": return "".join(f"{a} {b}\n" for a, b in merged)
    if mode == "total": return f"{sum(b - a + 1 for a, b in merged)}\n"
    out, cur = [], lo
    for a, b in merged:
        if b < cur: continue
        if a > hi: break
        if a > cur: out.append((cur, a - 1))
        cur = b + 1
        if cur > hi: break
    if cur <= hi: out.append((cur, hi))
    return "".join(f"{a} {b}\n" for a, b in out) or "none\n"

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(17)
def rand_ivs(n, span, width):
    out = ""
    for _ in range(n):
        a = rnd.randint(-span, span); out += f"{a} {a + rnd.randint(0, width)}\n"
    return out
examples = [
    case("merge", "merge\n8 10\n1 3\n2 6\n15 18\n17 20\n"),
    case("gaps", "gaps 0 20\n8 10\n1 3\n2 6\n15 18\n17 20\n"),
]
hidden = examples + [
    case("total", "total\n8 10\n1 3\n2 6\n15 18\n17 20\n"),
    case("adjacent-merge", "merge\n4 6\n1 3\n7 7\n9 9\n"),
    case("nested-and-equal", "merge\n1 100\n5 6\n1 100\n50 150\n-5 -2\n"),
    case("negative-and-zero", "merge\n-10 -3\n-3 0\n001 5\n-0 -0\n"),
    case("extremes-total", "total\n-2000000000 2000000000\n1999999999 3000000000\n"),
    case("no-intervals", "merge\n"),
    case("gaps-none", "gaps 3 8\n1 5\n6 10\n"),
    case("gaps-edges", "gaps -5 5\n-3 -3\n0 1\n5 9\n-20 -10\n"),
    case("bad-modes", "Merge\n1 2\n"),
    case("bad-gaps-args", "gaps 1\n1 2\n"),
    case("bad-interval-lines", "merge\n1 2\n3\n4 x\n"),
    case("bad-int-forms", "merge\n+1 2\n1 2 3\n 1 2\n1  2\n12345678901 5\n"),
    case("blank-lines", "merge\n\n  \n1 2\n\n3 4\n"),
    case("big", "merge\n" + rand_ivs(2000, 100000, 300)),
    case("big-gaps", "gaps -100000 100000\n" + rand_ivs(1500, 100000, 40)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
