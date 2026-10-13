import json, random, re, pathlib

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    mode = lines[0] if lines else ""
    if mode not in ("rank", "dense", "stable"): return "error: bad mode\n"
    ents, bad = [], 0
    for l in lines[1:]:
        if l.strip(" ") == "": continue
        t = l.split(" ")
        if len(t) != 2 or t[0] == "" or not re.fullmatch(r"-?[0-9]{1,9}", t[1]):
            bad += 1; continue
        ents.append((t[0], int(t[1])))
    out = []
    if mode == "stable":
        for n, sc in sorted(ents, key=lambda e: -e[1]): out.append(f"{n} {sc}")
    else:
        ents.sort(key=lambda e: (-e[1], e[0].encode()))
        rank, prev = 0, None
        for i, (n, sc) in enumerate(ents):
            if sc != prev:
                rank = i + 1 if mode == "rank" else rank + 1
                prev = sc
            out.append(f"{rank} {n} {sc}")
    if bad: out.append(f"skipped: {bad}")
    return "".join(x + "\n" for x in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(12)
names = ["ann", "Bob", "cat", "dan", "Eve", "fay", "gus", "zed", "al", "Al", "a", "b"]
def recs(n, lo, hi): return "".join(f"{rnd.choice(names)}{rnd.randint(0, 30) if rnd.random() < .7 else ''} {rnd.randint(lo, hi)}\n" for _ in range(n))
examples = [
    case("basic", "rank\nann 90\nbob 80\ncat 80\ndan 70\neve\nfay x1\n"),
    case("dense", "dense\nann 90\nbob 80\ncat 80\ndan 70\n"),
]
hidden = examples + [
    case("stable", "stable\nzed 5\nann 5\nbob 7\ncat 5\ndan 7\neve 1\n"),
    case("rank-ties", "rank\nb 10\na 10\nc 10\nd 9\ne 9\nf 8\n"),
    case("dense-ties", "dense\nb 10\na 10\nc 10\nd 9\ne 9\nf 8\n"),
    case("byte-order", "rank\nb 1\nB 1\na 1\nA 1\n_ 1\n1 1\n"),
    case("negative", "rank\nx -5\ny 0\nz -0\nw -10\nv 007\nu 7\n"),
    case("duplicate-names", "rank\nann 5\nann 5\nann 7\nbob 5\n"),
    case("bad-mode", "Rank\nann 1\n"),
    case("empty-mode", "\nann 1\n"),
    case("only-mode", "dense\n"),
    case("invalid-lines", "rank\nann\nann 1 2\n ann 1\nann  1\nann 1.5\nann +1\nann 1234567890\nann -\nann 5\n\n  \nbob 5\n"),
    case("all-invalid", "stable\nx\ny z\n"),
    case("blank-lines", "dense\n\nann 3\n\n  \nbob 4\n"),
    case("big-rank", "rank\n" + recs(1500, -20, 20)),
    case("big-stable", "stable\n" + recs(1500, -5, 5)),
    case("no-trailing-newline", "dense\na 1\nb 2"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
