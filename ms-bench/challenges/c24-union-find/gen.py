import json, random, pathlib

def solve(s):
    lines = [l for l in s.split("\n") if l.strip()]
    n = int(lines[0])
    par, sz, sets, out = list(range(n)), [1] * n, n, []
    def find(x):
        while par[x] != x:
            par[x] = par[par[x]]; x = par[x]
        return x
    for line in lines[1:]:
        p = line.split(" ")
        c = p[0]
        if c == "count":
            out.append(str(sets)); continue
        args = [int(a) for a in p[1:]]
        if any(a < 0 or a >= n for a in args):
            out.append("error"); continue
        if c == "size": out.append(str(sz[find(args[0])]))
        elif c == "connected": out.append("yes" if find(args[0]) == find(args[1]) else "no")
        elif c == "union":
            a, b = find(args[0]), find(args[1])
            if a == b: out.append("same")
            else:
                par[a] = b; sz[b] += sz[a]; sets -= 1; out.append("merged")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(24)
def rand_ops(n, m, bad=0.02, union_w=0.5):
    ops = [str(n)]
    for _ in range(m):
        def el():
            if rnd.random() < bad: return rnd.choice([-1, n, n + 5, -100])
            return rnd.randrange(n)
        r = rnd.random()
        if r < union_w: ops.append(f"union {el()} {el()}")
        elif r < union_w + .25: ops.append(f"connected {el()} {el()}")
        elif r < union_w + .45: ops.append(f"size {el()}")
        else: ops.append("count")
    return "\n".join(ops) + "\n"
examples = [
    case("basic", "5\nunion 0 1\nunion 1 2\nunion 0 2\nconnected 0 2\nconnected 0 3\nsize 1\ncount\nsize 9\n"),
    case("chain", "4\nunion 0 1\nunion 2 3\nunion 1 3\nsize 0\ncount\n"),
]
hidden = examples + [
    case("zero-elements", "0\ncount\nsize 0\nunion 0 0\n"),
    case("single", "1\nsize 0\ncount\nunion 0 0\nconnected 0 0\n"),
    case("out-of-range", "3\nunion 0 3\nunion -1 1\nconnected 2 7\nsize -5\ncount\nunion 0 2\ncount\n"),
    case("partial-bad-no-effect", "4\nunion 1 99\nconnected 1 99\nsize 1\ncount\n"),
    case("self-union", "3\nunion 1 1\ncount\nsize 1\n"),
    case("blank-lines", "\n4\n\nunion 0 1\n\ncount\n"),
    case("no-trailing-newline", "3\nunion 0 2\ncount"),
    case("long-chain", "50\n" + "".join(f"union {i} {i + 1}\n" for i in range(49)) + "size 0\nsize 49\ncount\nconnected 0 49\n"),
    case("random-small", rand_ops(10, 80)),
    case("random-mid", rand_ops(500, 3000)),
    case("random-large", rand_ops(20000, 9000, union_w=0.6)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
