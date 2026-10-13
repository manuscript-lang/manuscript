import json, random, pathlib
from collections import defaultdict

LEVELS = ["DEBUG", "INFO", "WARN", "ERROR"]
METHODS = {"GET", "POST", "PUT", "DELETE"}

def digits(s): return len(s) > 0 and all("0" <= c <= "9" for c in s)

def parse(line):
    f = line.split(" ")
    if len(f) != 6: return None
    ts, lv, m, path, st, lat = f
    if not ts or lv not in LEVELS or m not in METHODS: return None
    if not path.startswith("/") or not (len(st) == 3 and digits(st)): return None
    if not digits(lat) or len(lat) > 9: return None
    return lv, path, int(st), int(lat)

def solve(s):
    valid = bad = e5 = 0
    lv = {l: 0 for l in LEVELS}
    cnt, tot = defaultdict(int), defaultdict(int)
    for line in s.split("\n"):
        if not line.strip(): continue
        r = parse(line)
        if r is None: bad += 1; continue
        valid += 1; lv[r[0]] += 1
        if r[2] >= 500: e5 += 1
        cnt[r[1]] += 1; tot[r[1]] += r[3]
    out = [f"valid: {valid}", f"malformed: {bad}"] + [f"{l}: {lv[l]}" for l in LEVELS] + [f"5xx: {e5}", "top:"]
    for p in sorted(cnt, key=lambda p: (-cnt[p], p))[:3]:
        out.append(f"{p} {cnt[p]} avg={tot[p] // cnt[p]}")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(25)
paths = ["/", "/api/users", "/api/orders", "/health", "/static/app.js", "/login", "/a", "/b", "/c"]
def good(i):
    return f"2024-05-01T10:{i // 60 % 60:02d}:{i % 60:02d} {rnd.choice(LEVELS)} {rnd.choice(sorted(METHODS))} {rnd.choice(paths)} {rnd.choice([200, 200, 201, 301, 404, 500, 503])} {rnd.randint(0, 900)}"
def mangle(l):
    f = l.split(" ")
    k = rnd.randrange(9)
    if k == 0: f[1] = f[1].lower()
    elif k == 1: f[2] = "PATCH"
    elif k == 2: f[3] = f[3][1:] or "x"
    elif k == 3: f[4] = "20"
    elif k == 4: f[5] = "12ms"
    elif k == 5: f = f[:5]
    elif k == 6: f.append("extra")
    elif k == 7: return l + " "
    else: f[5] = ""
    return " ".join(f)
def rand_log(n, bad=0.1):
    ls = []
    for i in range(n):
        l = good(i)
        ls.append(mangle(l) if rnd.random() < bad else l)
        if rnd.random() < .03: ls.append(rnd.choice(["", "   "]))
    return "\n".join(ls) + "\n"
examples = [
    case("basic", "2024-05-01T10:00:00 INFO GET /api/users 200 12\n2024-05-01T10:00:01 ERROR POST /api/orders 503 250\nthis line is broken\n2024-05-01T10:00:02 INFO GET /api/users 200 15\n2024-05-01T10:00:03 WARN GET /health 404 1\n"),
    case("all-malformed", "x\n\nINFO GET / 200 1\n"),
]
hidden = examples + [
    case("empty", ""),
    case("only-blank", "\n  \n\n"),
    case("one-valid", "t DEBUG PUT /x 099 0\n"),
    case("tie-break-path", "t INFO GET /b 200 1\nt INFO GET /a 200 1\nt INFO GET /c 200 1\nt INFO GET /d 200 1\nt INFO GET /d 200 3\n"),
    case("floor-avg", "t INFO GET /p 200 1\nt INFO GET /p 200 2\nt INFO GET /p 200 2\n"),
    case("status-5xx", "t INFO GET /p 499 1\nt INFO GET /p 500 1\nt INFO GET /p 999 1\nt INFO GET /p 099 1\n"),
    case("spacing-and-case", "t INFO  GET /p 200 1\nt  INFO GET /p 200 1\n t INFO GET /p 200 1\nt info GET /p 200 1\nt INFO get /p 200 1\nt INFO GET p 200 1\nt INFO GET /p 2000 1\nt INFO GET /p 20a 1\nt INFO GET /p 200 -1\nt INFO GET /p 200 1234567890\nt INFO GET /p 200 123456789\n"),
    case("no-trailing-newline", "t ERROR POST /z 500 7"),
    case("random-small", rand_log(40)),
    case("random-mid", rand_log(600, .2)),
    case("random-large", rand_log(5000, .05)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
