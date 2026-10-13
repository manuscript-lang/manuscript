import json, random, re, pathlib, heapq

NAME = r"[a-z][a-z0-9_]*"
LINE = re.compile(rf"({NAME}):((?: {NAME})*)")

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    deps = {}
    for i, l in enumerate(lines, 1):
        if l.strip(" ") == "": continue
        m = LINE.fullmatch(l)
        if not m: return f"error: line {i}\n"
        name = m.group(1)
        ds = m.group(2).split() if m.group(2) else []
        deps.setdefault(name, set()).update(ds)
        for d in ds: deps.setdefault(d, set())
    indeg = {n: len(d) for n, d in deps.items()}
    rev = {n: [] for n in deps}
    for n, d in deps.items():
        for x in d: rev[x].append(n)
    heap = [n.encode() for n, k in indeg.items() if k == 0]
    heapq.heapify(heap)
    out = []
    while heap:
        n = heapq.heappop(heap).decode()
        out.append(n)
        for m in rev[n]:
            indeg[m] -= 1
            if indeg[m] == 0: heapq.heappush(heap, m.encode())
    if len(out) < len(deps): return "cycle\n"
    return "".join(x + "\n" for x in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(15)
def dag(n, maxdeps):
    names = [f"t{i}_{rnd.choice('abxyz')}" for i in range(n)]
    order = names[:]; rnd.shuffle(order)
    lines = []
    for i, nm in enumerate(order):
        ds = rnd.sample(order[:i], min(i, rnd.randint(0, maxdeps))) if i else []
        lines.append(f"{nm}:" + "".join(" " + d for d in ds))
    rnd.shuffle(lines)
    return "\n".join(lines) + "\n"
examples = [
    case("basic", "deploy: build test\nbuild: compile\ntest: build\ncompile:\ndocs:\n"),
    case("cycle", "a: b\nb: c\nc: a\n"),
]
hidden = examples + [
    case("empty", ""),
    case("deps-only-nodes", "app: lib util\n"),
    case("smallest-first", "z:\nm:\na:\nb: z\nc: a\n"),
    case("diamond", "top: left right\nleft: base\nright: base\nbase:\n"),
    case("merge-declarations", "a: b\na: c\nb:\nc: b\na: b\n"),
    case("self-dependency", "a: a\n"),
    case("cycle-with-tail", "x: y\ny: z\nz: y\nok:\n"),
    case("malformed-trailing", "ok:\na: b \n"),
    case("malformed-upper-after-blank", "\n\nok:\n\nBad: x\n"),
    case("malformed-beats-cycle", "a: b\nb: a\nc:d\n"),
    case("underscore-digit-names", "a_1: b_2\nb_2: c3\nc3:\nx_:\n"),
    case("big-dag", dag(150, 4)),
    case("big-chain", "".join(f"n{i:03d}: n{i+1:03d}\n" for i in range(0, 120)) + "n120:\n"),
    case("no-trailing-newline", "b: a\na:"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
