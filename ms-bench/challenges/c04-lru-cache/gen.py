import json, random, pathlib
from collections import OrderedDict

def solve(s):
    lines = [l for l in s.split("\n") if l.strip()]
    cap, od, out = int(lines[0]), OrderedDict(), []
    for l in lines[1:]:
        p = l.split()
        if p[0] == "put":
            od[p[1]] = p[2]; od.move_to_end(p[1])
            if len(od) > cap: od.popitem(last=False)
        elif p[0] == "get":
            if p[1] in od: od.move_to_end(p[1]); out.append(od[p[1]])
            else: out.append("miss")
        else: out.append(" ".join(reversed(od)))
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(4)
def rand_ops(cap, n, nk):
    ops = [str(cap)]
    for _ in range(n):
        k = f"k{rnd.randint(1, nk)}"
        r = rnd.random()
        ops.append(f"put {k} v{rnd.randint(0, 99)}" if r < .5 else f"get {k}" if r < .9 else "keys")
    return "\n".join(ops) + "\n"
examples = [case("basic", "2\nput a 1\nput b 2\nget a\nput c 3\nget b\nkeys\n")]
hidden = examples + [
    case("cap1", "1\nput a 1\nput b 2\nget a\nget b\nkeys\n"), case("empty-keys", "3\nkeys\n"),
    case("update-refreshes", "2\nput a 1\nput b 2\nput a 9\nput c 3\nget a\nget b\nkeys\n"),
    case("get-refreshes", "2\nput a 1\nput b 2\nget a\nput c 3\nkeys\n"), case("miss-no-insert", "2\nget x\nkeys\n"),
    case("blank-lines", "2\n\nput a 1\n\nget a\n"),
    case("random-small", rand_ops(3, 200, 6)), case("random-wide", rand_ops(50, 5000, 80)),
    case("random-huge", rand_ops(500, 30000, 1000)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
