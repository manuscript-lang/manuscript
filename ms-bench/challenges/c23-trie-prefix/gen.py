import json, random, pathlib

def solve(s):
    words, out = set(), []
    for line in s.split("\n"):
        if not line.strip():
            continue
        p = line.split(" ")
        c = p[0]
        if c == "insert":
            out.append("exists" if p[1] in words else "added"); words.add(p[1])
        elif c == "has": out.append("yes" if p[1] in words else "no")
        elif c == "count": out.append(str(sum(w.startswith(p[1]) for w in words)))
        elif c == "complete":
            m = sorted(w for w in words if w.startswith(p[1]))[:int(p[2])]
            out.append(" ".join(m) if m else "none")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(23)
def word(alpha, lo, hi): return "".join(rnd.choice(alpha) for _ in range(rnd.randint(lo, hi)))
def rand_ops(n, alpha, lo, hi, pool=None):
    pool = pool or [word(alpha, lo, hi) for _ in range(n // 3)]
    ops = []
    for _ in range(n):
        r = rnd.random()
        w = rnd.choice(pool)
        pre = w[:rnd.randint(1, len(w))]
        if r < .4: ops.append(f"insert {w}")
        elif r < .5: ops.append(f"has {w}")
        elif r < .75: ops.append(f"count {pre}")
        else: ops.append(f"complete {pre} {rnd.randint(1, 6)}")
    return "\n".join(ops) + "\n"
examples = [
    case("basic", "insert car\ninsert card\ninsert care\ninsert cat\ninsert car\ncount car\ncount ca\ncount d\ncomplete ca 3\ncomplete car 10\ncomplete x 2\nhas cat\nhas ca\n"),
    case("prefix-words", "insert a\ninsert ab\ninsert abc\ncount a\ncomplete a 2\nhas ab\n"),
]
hidden = examples + [
    case("empty-input", ""),
    case("queries-on-empty", "count a\nhas a\ncomplete a 3\n"),
    case("duplicates", "insert zz\ninsert zz\ninsert zz\ncount z\ncount zz\ncount zzz\ncomplete z 5\n"),
    case("k-limit", "insert b\ninsert ba\ninsert bab\ninsert bb\ninsert bba\ncomplete b 1\ncomplete b 4\ncomplete b 99\ncomplete ba 2\n"),
    case("order-not-insertion", "insert dog\ninsert door\ninsert do\ninsert dot\ncomplete do 4\ncomplete do 2\n"),
    case("blank-lines", "\ninsert a\n\ncount a\n\n"),
    case("no-trailing-newline", "insert hi\ncount h"),
    case("random-small", rand_ops(80, "ab", 1, 4)),
    case("random-dense", rand_ops(1500, "abc", 1, 6)),
    case("random-large", rand_ops(4000, "abcdefghijklmnopqrstuvwxyz", 2, 10)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
