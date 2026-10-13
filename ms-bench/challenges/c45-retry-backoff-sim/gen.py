import json, random, pathlib

def solve(s):
    pol = dict(base=100, factor=2, cap=5000, mx=5, jit=0, dl=0, seed=1)
    downs, limit, reqs = [], None, []
    for line in s.split("\n"):
        t = line.replace("\t", " ").split()
        if not t: continue
        if t[0] == "policy":
            v = list(map(int, t[1:]))
            pol = dict(zip(["base", "factor", "cap", "mx", "jit", "dl", "seed"], v))
        elif t[0] == "down": downs.append((int(t[1]), int(t[2])))
        elif t[0] == "limit": limit = (int(t[1]), int(t[2]))
        elif t[0] == "req": reqs.append(dict(id=t[1], start=int(t[2]), k=1, t=int(t[2]), status=None, done=0))
    state = pol["seed"]
    acc, log = [], []
    while True:
        pend = [r for r in reqs if r["status"] is None]
        if not pend: break
        r = min(pend, key=lambda r: (r["t"], reqs.index(r)))
        t, k = r["t"], r["k"]
        res, ra = None, 0
        if any(a <= t < b for a, b in downs): res = "down"
        else:
            if limit:
                inwin = [a for a in acc if a > t - limit[0]]
                if len(inwin) >= limit[1]: res = "limited"; ra = min(inwin) + limit[0] - t
            if res is None:
                acc.append(t); r["status"] = "ok"; r["done"] = t
                log.append(f"t={t} {r['id']} #{k} ok"); continue
        r["done"] = t
        if k == pol["mx"]:
            r["status"] = "gave-up"; log.append(f"t={t} {r['id']} #{k} {res} gave-up"); continue
        d = min(pol["cap"], pol["base"])
        for _ in range(k - 1): d = min(pol["cap"], d * pol["factor"])
        state = state * 48271 % 2147483647
        rr = state % 1000
        d2 = max(1, d - d * pol["jit"] * rr // 100000)
        wait = max(d2, ra) if res == "limited" else d2
        nt = t + wait
        if pol["dl"] > 0 and nt > r["start"] + pol["dl"]:
            r["status"] = "expired"; log.append(f"t={t} {r['id']} #{k} {res} expired"); continue
        log.append(f"t={t} {r['id']} #{k} {res} retry@{nt}")
        r["t"] = nt; r["k"] = k + 1
    out = list(log)
    for r in reqs: out.append(f"{r['id']} {r['status']} attempts={r['k']} done={r['done']}")
    ok = sum(1 for r in reqs if r["status"] == "ok")
    out.append(f"total ok={ok} failed={len(reqs) - ok} attempts={sum(r['k'] for r in reqs)}")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(45)
def L(*xs): return "".join(x + "\n" for x in xs)

examples = [case("basic", L("policy 100 2 1000 4 0 0 7", "down 0 250", "req a 0", "req b 50", "req c 400"))]
big = ["policy 50 2 3000 8 30 4200 12345", "limit 1000 5"]
for a, b in [(500, 1500), (4000, 4600), (9000, 12000)]: big.append(f"down {a} {b}")
for i in range(80): big.append(f"req r{i:02d} {rnd.choice([0, 0, 100, 250, 500, 1000, 2000, 3000, 5000, 8000]) + rnd.randint(0, 40)}")
hidden = examples + [
    case("no-requests", L("policy 10 2 100 3 0 0 1", "down 0 10")),
    case("no-failures", L("req a 5", "req b 5", "req c 0", "req d 100")),
    case("default-policy", L("down 0 1000", "req a 0")),
    case("backoff-cap", L("policy 10 3 100 8 0 0 1", "down 0 100000", "req a 0")),
    case("base-above-cap", L("policy 500 2 200 4 0 0 1", "down 0 100000", "req a 0")),
    case("factor-one", L("policy 40 1 1000 5 0 0 1", "down 0 100000", "req a 0")),
    case("max-one", L("policy 40 2 1000 1 50 0 9", "down 0 100", "req a 0", "req b 200")),
    case("jitter", L("policy 1000 2 100000 6 90 0 2021", "down 0 1000000", "req a 0", "req b 0", "req c 7")),
    case("jitter-min-one", L("policy 1 1 1 4 90 0 77", "down 0 1000", "req a 0")),
    case("deadline", L("policy 100 2 5000 10 20 700 31", "down 0 5000", "req a 0", "req b 100", "req c 650", "req d 4900")),
    case("max-before-deadline", L("policy 100 2 5000 3 0 400 5", "down 0 500", "req a 0")),
    case("rate-limit", L("policy 50 2 400 6 0 0 3", "limit 100 2", "req a 0", "req b 0", "req c 0", "req d 0", "req e 10")),
    case("retry-after-wins", L("policy 1 1 1 5 0 0 4", "limit 1000 1", "req a 0", "req b 1", "req c 2")),
    case("ties-by-input-order", L("policy 10 1 10 3 0 0 8", "down 0 15", "req z 5", "req y 5", "req x 5", "req w 0")),
    case("overlapping-downs", L("policy 30 2 500 6 10 0 6", "down 100 200", "down 150 400", "down 0 50", "req a 0", "req b 120", "req c 60")),
    case("config-order", L("req a 0", "down 0 200", "limit 10 1", "policy 20 2 300 5 40 0 99", "req b 1", "policy 25 3 400 4 0 0 100", "req c 2")),
    case("whitespace", "\n  policy\t10  2  100\t3 0 0 1 \n\tdown  0   30\n\n req   a\t0\n"),
    case("random-large", L(*big)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
