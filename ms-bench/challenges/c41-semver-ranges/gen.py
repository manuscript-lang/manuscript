import json, random, pathlib, re, functools

NUM = re.compile(r"^(0|[1-9][0-9]{0,8})$")

def ident_ok(s):
    return s != "" and all(c.isascii() and (c.isalnum() or c == "-") for c in s) and (not s.isdigit() or NUM.match(s) is not None)

def parse_pre(s):
    ids = s.split(".")
    if not all(ident_ok(i) for i in ids): return None
    return ids

def parse_version(s):
    pre = []
    if "-" in s:
        s, p = s.split("-", 1)
        pre = parse_pre(p)
        if pre is None: return None
    parts = s.split(".")
    if len(parts) != 3 or not all(NUM.match(p) for p in parts): return None
    return (int(parts[0]), int(parts[1]), int(parts[2]), tuple(pre))

def cmp_id(a, b):
    an, bn = a.isdigit(), b.isdigit()
    if an and bn: return (int(a) > int(b)) - (int(a) < int(b))
    if an: return -1
    if bn: return 1
    ab, bb = a.encode(), b.encode()
    return (ab > bb) - (ab < bb)

def cmp_ver(a, b):
    for i in range(3):
        if a[i] != b[i]: return -1 if a[i] < b[i] else 1
    pa, pb = a[3], b[3]
    if not pa and not pb: return 0
    if not pa: return 1
    if not pb: return -1
    for x, y in zip(pa, pb):
        c = cmp_id(x, y)
        if c: return c
    return (len(pa) > len(pb)) - (len(pa) < len(pb))

def parse_partial(tok):
    """returns (n, M, m, p, pre) or None"""
    if tok in ("x", "X", "*"): return (0, 0, 0, 0, ())
    pre = ()
    if "-" in tok:
        base, p = tok.split("-", 1)
        ids = parse_pre(p)
        if ids is None: return None
        pre = tuple(ids)
    else:
        base = tok
    parts = base.split(".")
    if len(parts) > 3: return None
    vals = []
    wild = False
    for q in parts:
        if q in ("x", "X", "*"): wild = True
        else:
            if wild or not NUM.match(q): return None
            vals.append(int(q))
    if pre and len(vals) != 3: return None
    n = len(vals)
    v = vals + [0] * (3 - n)
    return (n, v[0], v[1], v[2], pre)

NEVER = ("<", (0, 0, 0, ()))

def V(M, m, p, pre=()): return (M, m, p, tuple(pre))

def term_comps(op, P):
    n, M, m, p, pre = P
    full = V(M, m, p, pre)
    fill = V(M, m, p, pre if n == 3 else ())
    n1, n2 = V(M + 1, 0, 0), V(M, m + 1, 0)
    if op in ("", "="):
        return [] if n == 0 else [(">=", V(M, 0, 0)), ("<", n1)] if n == 1 else [(">=", V(M, m, 0)), ("<", n2)] if n == 2 else [("==", full)]
    if op == ">":
        return [NEVER] if n == 0 else [(">=", n1)] if n == 1 else [(">=", n2)] if n == 2 else [(">", full)]
    if op == ">=":
        return [] if n == 0 else [(">=", fill)]
    if op == "<":
        return [NEVER] if n == 0 else [("<", fill)]
    if op == "<=":
        return [] if n == 0 else [("<", n1)] if n == 1 else [("<", n2)] if n == 2 else [("<=", full)]
    if op == "~":
        return [] if n == 0 else [(">=", V(M, 0, 0)), ("<", n1)] if n == 1 else [(">=", V(M, m, 0)), ("<", n2)] if n == 2 else [(">=", full), ("<", n2)]
    if op == "^":
        if n == 0: return []
        if n == 1: return [(">=", V(M, 0, 0)), ("<", n1)]
        if n == 2: return [(">=", V(M, m, 0)), ("<", n1 if M > 0 else n2)]
        if M > 0: return [(">=", full), ("<", n1)]
        if m > 0: return [(">=", full), ("<", n2)]
        return [(">=", full), ("<", V(0, 0, p + 1))]

OPS = [">=", "<=", ">", "<", "=", "^", "~"]

def parse_range(tokens):
    sets, cur = [], []
    for t in tokens:
        if t == "||": sets.append(cur); cur = []
        else: cur.append(t)
    sets.append(cur)
    out = []
    for st in sets:
        comps, i = [], 0
        while i < len(st):
            if i + 1 < len(st) and st[i + 1] == "-":
                if i + 2 >= len(st): return None
                a, b = parse_partial(st[i]), parse_partial(st[i + 2])
                if a is None or b is None: return None
                if a[0] > 0: comps.append((">=", V(a[1], a[2], a[3], a[4] if a[0] == 3 else ())))
                n, M, m, p, pre = b
                if n == 3: comps.append(("<=", V(M, m, p, pre)))
                elif n == 2: comps.append(("<", V(M, m + 1, 0)))
                elif n == 1: comps.append(("<", V(M + 1, 0, 0)))
                i += 3
                continue
            t = st[i]
            if t == "-": return None
            op = ""
            for o in OPS:
                if t.startswith(o): op = o; break
            P = parse_partial(t[len(op):])
            if P is None: return None
            comps += term_comps(op, P)
            i += 1
        out.append(comps)
    return out

def holds(c, v):
    k = cmp_ver(v, c[1])
    return {">=": k >= 0, ">": k > 0, "<": k < 0, "<=": k <= 0, "==": k == 0}[c[0]]

def satisfies(rng, v):
    for comps in rng:
        if not all(holds(c, v) for c in comps): continue
        if v[3] and not any(c[1][3] and c[1][:3] == v[:3] for c in comps): continue
        return True
    return False

def solve(s):
    pool, out = [], []   # pool: list of (text, ver)
    for line in s.split("\n"):
        t = line.replace("\t", " ").split()
        if not t: continue
        c = t[0]
        if c == "pool":
            seen, pool, skipped = set(), [], 0
            for a in t[1:]:
                v = parse_version(a)
                if v is None: skipped += 1; continue
                if a in seen: continue
                seen.add(a); pool.append((a, v))
            pool.sort(key=functools.cmp_to_key(lambda x, y: cmp_ver(x[1], y[1])))
            out.append(f"pool {len(pool)} skipped {skipped}")
        elif c in ("max", "all"):
            r = parse_range(t[1:])
            if r is None: out.append("invalid range"); continue
            ok = [a for a, v in pool if satisfies(r, v)]
            if not ok: out.append("none")
            elif c == "max": out.append(ok[-1])
            else: out.append(" ".join(ok))
        elif c == "test" and len(t) >= 2:
            v = parse_version(t[1])
            if v is None: out.append("invalid version"); continue
            r = parse_range(t[2:])
            if r is None: out.append("invalid range"); continue
            out.append("true" if satisfies(r, v) else "false")
        else:
            out.append("error: bad command")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(41)

POOL = "0.0.1 0.0.3 0.1.0 0.2.3 0.2.9 0.3.0 0.9.9 1.0.0-alpha 1.0.0-alpha.1 1.0.0-alpha.beta 1.0.0-beta 1.0.0-beta.2 1.0.0-beta.11 1.0.0-rc.1 1.0.0 1.0.1 1.2.0 1.2.3-beta.2 1.2.3-beta.4 1.2.3 1.2.4 1.3.0 1.9.9 2.0.0-0 2.0.0 2.0.1 2.1.0 2.1.5 3.0.0 3.1.4 10.0.0 10.20.30 0.0.0"
def rand_range():
    def partial():
        k = rnd.random()
        if k < .5: return f"{rnd.randint(0,3)}.{rnd.randint(0,3)}.{rnd.randint(0,5)}"
        if k < .7: return f"{rnd.randint(0,3)}.{rnd.randint(0,3)}"
        if k < .8: return f"{rnd.randint(0,3)}.x"
        if k < .9: return str(rnd.randint(0,3))
        return rnd.choice(["1.0.0-beta", "1.2.3-beta.2", "2.0.0-0", "*", "x", "1.0.0-alpha.1"])
    sets = []
    for _ in range(rnd.randint(1, 3)):
        terms = []
        for _ in range(rnd.randint(1, 3)):
            if rnd.random() < .15: terms.append(f"{partial()} - {partial()}")
            else: terms.append(rnd.choice(["", "", ">=", "<", ">", "<=", "^", "~", "^", "~", "="]) + partial())
        sets.append(" ".join(terms))
    return " || ".join(sets)

examples = [case("basic", "pool 1.2.3 1.3.0 2.0.0 2.1.0-rc.1 0.9.9 bad\nmax ^1.2.0\nall >=1.2.3 <2.0.0 || 0.x\nmax *\ntest 2.1.0-rc.1 >=2.1.0-alpha\ntest 2.1.0-rc.1 >=2.0.0\n")]
rl = []
for _ in range(120):
    cmd = rnd.choice(["max", "all", "all"])
    rl.append(f"{cmd} {rand_range()}")
    if rnd.random() < .3: rl.append(f"test {rnd.choice(POOL.split())} {rand_range()}")
hidden = examples + [
    case("caret-tilde", f"pool {POOL}\nmax ^1.2.3\nmax ^0.2.3\nmax ^0.0.3\nmax ^0.0\nmax ^0\nmax ^1.2\nmax ~1.2.3\nmax ~1.2\nmax ~1\nmax ~0.2\nall ^0.2.3\nall ~1.0.0\nall ^1\n"),
    case("comparators", f"pool {POOL}\nall >=1.2.3 <1.9.9\nall >1.2\nall >1\nall <=1.2\nall <=1\nall <1\nall <1.2\nall >=1.x\nall =1.2\nall 1.2.3\nall =1.2.3\nall >0.9.9 <=1.0.1\n"),
    case("wildcards", f"pool {POOL}\nall *\nall x\nall X\nall\nall 1.x\nall 1.*.x\nall 2.x.x\nall >=*\nall >*\nall <*\nall <=*\nall =*\nall ^*\nall ~x\nmax 1.x.x\n"),
    case("hyphen", f"pool {POOL}\nall 1.2.3 - 1.9.9\nall 1 - 2\nall 1.2 - 1.3\nall 0.2.3 - 1\nall * - 0.3\nall 1.2.3 - *\nall 1.0.0-alpha - 1.0.0-beta\nall 1 - 2 || 10\n"),
    case("hyphen-invalid", f"pool {POOL}\nall 1.0.0 -\nall - 1.0.0\nall 1 - - 2\nall >=1 - 2\nall 1 - ^2\nall 1.0.0 - 2.0.0 -\nall 1 -2\nmax -\n"),
    case("prerelease-rule", f"pool {POOL}\nall >=1.0.0-alpha <1.0.0\nall >=1.2.3-beta.2 <2.0.0\nall ^1.2.3-beta.2\nall ~1.2.3-beta.3\nall 1.0.0-beta\nall >1.0.0-beta.2\nall <1.0.0\nall <2.0.0\nall >=2.0.0-0 <2.0.1\nall 1.0.0-alpha - 1.0.0\nall 1.2.3-beta.2 - 1.2.3-beta.4\n"),
    case("precedence", "pool 1.0.0-alpha 1.0.0-alpha.1 1.0.0-alpha.beta 1.0.0-beta 1.0.0-beta.2 1.0.0-beta.11 1.0.0-rc.1 1.0.0 1.0.0-9 1.0.0-10 1.0.0-a-b 1.0.0-A\nall *\nall >=1.0.0-0\nall >=1.0.0-0 <1.0.0\nmax >=1.0.0-0 <1.0.0\nall >1.0.0-alpha.1 <1.0.0-beta.2\n"),
    case("or-sets", f"pool {POOL}\nall ^0.2.3 || ^1.9.0 || 10.x\nall 1.2.3 || || 3.0.0\nall || 3.0.0\nall 3.0.0 ||\nall ||\nmax <0.1.0 || >=10\nall ^1.0.0 <1.2.0 || ~2.1.0\n"),
    case("invalid-ranges", f"pool {POOL}\nmax 1.2.3.4\nmax 01.2.3\nmax 1.x.3\nmax a.b.c\nmax >=\nmax ^\nmax ~~1\nmax >>1\nmax =>1\nmax 1.2.3+build\nmax 1.0.0-\nmax 1.0-beta\nmax 1.0.0-be..ta\nmax 1.0.0-01\nmax 1234567890\nmax 1.0.0 | 2.0.0\nmax ^1.2.3 junk\nmax 1.0.0-a_b\nall >= 1.0.0\n"),
    case("test-cmd", "pool\ntest 1.2.3 ^1.0.0\ntest 1.2.3\ntest 1.2.3-beta ^1.0.0\ntest 1.2.3-beta ^1.2.3-alpha\ntest 1.2.3-beta ^1.2.4-alpha\ntest 1.2 ^1.0.0\ntest 01.2.3 ^bad\ntest 1.2.3 ^bad\ntest 1.2.3+b *\ntest 0.0.0-a <0.0.0\ntest 0.0.0 >*\ntest 0.0.0 <*\ntest\ntest 1.0.0 || 2.0.0\ntest 2.0.0 1.0.0 || 2.0.0\ntest 5.5.5 >=5.5.5 <=5.5.5\n"),
    case("pool-handling", "pool 1.0.0 1.0.0 2.0.0 x 1.0 01.0.0 1.0.0-a+b 3.0.0\nall\nmax >1\nmax\npool\nmax\nall *\nmax *\npool 9.9.9\nall\nmax <9\nmax\nPOOL 1.0.0\nmax 1.x extra\nfoo\npool\t4.0.0\t 4.0.0 \n  max   >=4  \nall\n"),
    case("whitespace-mixed", "\n  pool\t1.0.0   2.0.0\t\n\n \tmax\t^1\t||\t2\n\n   all  >=1  <=2.0.0\t \nMAX *\nmax  1.0.0  -  2.0.0\n"),
    case("random-large", f"pool {POOL}\n" + "\n".join(rl) + "\n"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
