import json, random, pathlib, heapq

def solve(s):
    h, seq, out = [], 0, []
    for line in s.split("\n"):
        if not line.strip():
            continue
        p = line.split(" ")
        c = p[0]
        if c == "push":
            heapq.heappush(h, (int(p[1]), seq, p[2])); seq += 1
        elif c == "pop":
            if h:
                pr, _, n = heapq.heappop(h); out.append(f"{n} {pr}")
            else: out.append("empty")
        elif c == "peek":
            out.append(f"{h[0][2]} {h[0][0]}" if h else "empty")
        elif c == "size": out.append(str(len(h)))
        elif c == "drain":
            if not h: out.append("empty")
            while h:
                pr, _, n = heapq.heappop(h); out.append(f"{n} {pr}")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(22)
def rand_ops(n, prio_range, names):
    ops = []
    for _ in range(n):
        r = rnd.random()
        if r < .55: ops.append(f"push {rnd.randint(*prio_range)} {rnd.choice(names)}")
        elif r < .8: ops.append("pop")
        elif r < .9: ops.append("peek")
        elif r < .98: ops.append("size")
        else: ops.append("drain")
    return "\n".join(ops) + "\n"
examples = [
    case("basic", "push 5 write\npush 1 plan\npush 5 test\npush 3 build\npop\npeek\nsize\ndrain\npop\n"),
    case("empty", "pop\npeek\nsize\ndrain\n"),
]
hidden = examples + [
    case("empty-input", ""),
    case("ties-fifo", "push 2 a\npush 2 b\npush 2 c\npush 1 d\npush 2 e\ndrain\n"),
    case("negative", "push -5 low\npush 0 zero\npush 7 high\npush -5 low2\ndrain\nsize\n"),
    case("leading-zero-and-neg", "push 007 x\npush -0 y\npush -010 z\ndrain\n"),
    case("same-name", "push 3 a\npush 1 a\npush 3 a\npop\npop\npop\npop\n"),
    case("blank-lines", "\npush 1 a\n\npop\n\n"),
    case("no-trailing-newline", "push 4 q\npeek"),
    case("random-small", rand_ops(80, (-5, 5), ["a", "b", "c", "d"])),
    case("random-ties", rand_ops(1500, (0, 3), [f"n{i}" for i in range(30)])),
    case("random-large", rand_ops(5000, (-1000000, 1000000), [f"job{i}" for i in range(300)])),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
