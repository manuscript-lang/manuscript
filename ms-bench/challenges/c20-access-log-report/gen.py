import json, random, re, pathlib, math

MON = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
METHODS = {"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"}
IP = re.compile(r"([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})")
TS = re.compile(r"([0-9]{2})/([A-Za-z]{3})/([0-9]{4}):([0-9]{2}):([0-9]{2}):([0-9]{2}) [+-][0-9]{4}")

def parse(line):
    parts = line.split('"')
    if len(parts) != 3: return None
    before, req, after = parts
    if not before.endswith(" ") or not after.startswith(" "): return None
    b = before[:-1].split(" ")
    if len(b) != 5: return None
    ip, ident, user, t1, t2 = b
    m = IP.fullmatch(ip)
    if not m or any(int(g) > 255 for g in m.groups()): return None
    for tok in (ident, user):
        if tok == "" or "[" in tok: return None
    if not (t1.startswith("[") and t2.endswith("]")): return None
    t = TS.fullmatch(t1[1:] + " " + t2[:-1])
    if not t: return None
    dd, mon, _, hh, mm, ss = t.groups()
    if not (1 <= int(dd) <= 31 and mon in MON and int(hh) <= 23 and int(mm) <= 59 and int(ss) <= 59): return None
    r = req.split(" ")
    if len(r) != 3 or r[0] not in METHODS or not r[1].startswith("/") or r[2] not in ("HTTP/1.0", "HTTP/1.1", "HTTP/2.0"): return None
    a = after[1:].split(" ")
    if len(a) != 3: return None
    status, nbytes, tm = a
    if not re.fullmatch(r"[0-9]{3}", status) or not 100 <= int(status) <= 599: return None
    if nbytes != "-" and not re.fullmatch(r"[0-9]{1,10}", nbytes): return None
    mt = re.fullmatch(r"([0-9]{1,4})\.([0-9]{3})", tm)
    if not mt: return None
    target = r[1]
    cut = min([i for i in (target.find("?"), target.find("#")) if i >= 0], default=len(target))
    route = "/".join(":id" if seg.isdigit() and seg.isascii() else seg for seg in target[:cut].split("/"))
    return dict(ip=ip, hour=hh, route=f"{r[0]} {route}", status=int(status), bytes=0 if nbytes == "-" else int(nbytes), ms=int(mt.group(1)) * 1000 + int(mt.group(2)))

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    recs, bad = [], 0
    for l in lines:
        if l.strip(" ") == "": continue
        r = parse(l)
        if r: recs.append(r)
        else: bad += 1
    out = [f"requests={len(recs)} malformed={bad} bytes={sum(r['bytes'] for r in recs)} ips={len({r['ip'] for r in recs})}"]
    cls = [sum(1 for r in recs if r["status"] // 100 == c) for c in range(1, 6)]
    out.append("status " + " ".join(f"{c}xx={n}" for c, n in zip(range(1, 6), cls)))
    hours = {}
    for r in recs: hours[r["hour"]] = hours.get(r["hour"], 0) + 1
    out.append("hours " + (" ".join(f"{h}={hours[h]}" for h in sorted(hours)) if hours else "none"))
    routes = {}
    for r in recs: routes.setdefault(r["route"], []).append(r)
    if not routes: out.append("endpoints none")
    else:
        top = sorted(routes.items(), key=lambda kv: (-len(kv[1]), kv[0].encode()))[:5]
        for name, rs in top:
            ts = sorted(r["ms"] for r in rs)
            n = len(ts)
            avg = (2 * sum(ts) + n) // (2 * n)
            p95 = ts[(95 * n + 99) // 100 - 1]
            errs = sum(1 for r in rs if r["status"] >= 400)
            out.append(f"endpoint {n} {name} avg={avg}ms p95={p95}ms errors={errs}")
    return "".join(x + "\n" for x in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(20)
def line(ip="203.0.113.9", ident="-", user="-", ts="10/Oct/2023:13:55:36 +0000", req="GET /api/users/42 HTTP/1.1", status="200", nbytes="2326", tm="0.123"):
    return f'{ip} {ident} {user} [{ts}] "{req}" {status} {nbytes} {tm}'
routes = ["GET /", "GET /api/users/{n}", "GET /api/users/{n}/orders/{n}", "POST /api/orders", "PUT /api/users/{n}", "DELETE /api/users/{n}", "GET /static/app.js?v={n}", "GET /health", "HEAD /health", "POST /login", "GET /search?q=term&page={n}", "PATCH /api/items/{n}#frag"]
statuses = [200] * 12 + [201, 204, 301, 302, 304, 400, 401, 403, 404, 404, 500, 502, 503]
def gen_line():
    req = rnd.choice(routes).replace("{n}", str(rnd.randint(1, 9999)))
    ip = f"{rnd.choice([10, 192, 203])}.{rnd.randint(0, 3)}.{rnd.randint(0, 2)}.{rnd.randint(1, 20)}"
    ts = f"{rnd.randint(1, 28):02d}/{rnd.choice(MON)}/2023:{rnd.randint(0, 23):02d}:{rnd.randint(0, 59):02d}:{rnd.randint(0, 59):02d} {rnd.choice(['+0000', '-0700', '+0530'])}"
    ver = rnd.choice(["HTTP/1.1", "HTTP/1.1", "HTTP/2.0", "HTTP/1.0"])
    return line(ip=ip, user=rnd.choice(["-", "-", "alice", "bob"]), ts=ts, req=req.replace(" ", " ", 1) + " " + ver, status=str(rnd.choice(statuses)), nbytes=rnd.choice(["-", str(rnd.randint(0, 50000))]), tm=f"{rnd.choice([0, 0, 0, 1, 2])}.{rnd.randint(0, 999):03d}")
big_lines = [gen_line() for _ in range(1500)]
for bad in ['garbage', '1.2.3.4 - - [bad] "GET / HTTP/1.1" 200 1 0.001', line(status="99"), line(tm="1.5")]:
    big_lines.insert(rnd.randint(0, len(big_lines)), bad)
ex = [
    line(user="alice", req="GET /api/users/42?verbose=1 HTTP/1.1"),
    line(user="-", ts="10/Oct/2023:13:56:01 +0000", req="GET /api/users/7 HTTP/1.1", status="404", nbytes="-", tm="0.010"),
    line(ip="198.51.100.2", ts="10/Oct/2023:14:02:11 +0000", req="POST /login HTTP/1.1", status="302", nbytes="0", tm="0.250"),
    "not a log line",
]
examples = [case("basic", "\n".join(ex) + "\n"), case("empty", "")]
hidden = examples + [
    case("route-normalization-1", "\n".join([line(req=f"GET {t} HTTP/1.1") for t in ["/a/1/b/22", "/a//b/", "/a/12?x=1/2", "/a/12#f?x", "/"]]) + "\n"),
    case("route-normalization-2", "\n".join([line(req=f"GET {t} HTTP/1.1") for t in ["/?q=1", "/v1/users/007/x", "/users/1a", "/9/", "//3"]]) + "\n"),
    case("percentile-and-average", "\n".join([line(req="GET /p HTTP/1.1", tm=f"0.{t:03d}") for t in [5, 1, 4, 2, 3]] + [line(req="GET /q HTTP/1.1", tm=f"0.{t:03d}") for t in range(1, 21)] + [line(req="GET /r HTTP/1.1", tm="1.001"), line(req="GET /r HTTP/1.1", tm="1.002")]) + "\n"),
    case("ties-and-top-five", "\n".join([line(req=f"{m} /{p} HTTP/1.1") for m, p in [("GET", "b"), ("GET", "a"), ("POST", "a"), ("GET", "c"), ("GET", "d"), ("GET", "e"), ("GET", "f")]] + [line(req="GET /z HTTP/1.1")] * 2) + "\n"),
    case("status-classes", "\n".join([line(status=s) for s in ["100", "101", "200", "204", "301", "304", "400", "404", "499", "500", "599"]]) + "\n"),
    case("bytes-and-ips", "\n".join([line(ip="1.1.1.1", nbytes="-"), line(ip="1.1.1.1", nbytes="10"), line(ip="01.1.1.1", nbytes="4294967295"), line(ip="255.255.255.255", nbytes="0")]) + "\n"),
    case("hours", "\n".join([line(ts=f"01/Jan/2024:{h:02d}:00:00 +0000") for h in [23, 0, 0, 9, 23, 23, 12]]) + "\n"),
    case("malformed-ip", "\n".join([line(ip=i) for i in ["256.1.1.1", "1.2.3", "1.2.3.4.5", "1.2.3.a", "1234.1.1.1", "1.2.3.", " 1.2.3.4", "-"]]) + "\n"),
    case("malformed-time-and-bytes", "\n".join([line(tm=t) for t in ["1", "1.5", "1.5000", "-1.000", "12345.000", ".500", "1.50a"]] + [line(nbytes=b) for b in ["", "--", "12345678901", "1.5", "-5", "0x10"]]) + "\n"),
    case("malformed-timestamp", "\n".join([line(ts=t) for t in ["32/Oct/2023:13:55:36 +0000", "00/Oct/2023:13:55:36 +0000", "10/oct/2023:13:55:36 +0000", "10/Oct/2023:24:55:36 +0000", "10/Oct/2023:13:60:36 +0000", "10/Oct/2023:13:55:60 +0000", "10/Oct/2023:13:55:36 0000", "10/Oct/2023:13:55:36 +000", "10/Oct/23:13:55:36 +0000", "31/Feb/2023:01:02:03 -0000"]]) + "\n"),
    case("malformed-request", "\n".join([line(req=r) for r in ["GET / HTTP/1.1", "get / HTTP/1.1", "TRACE / HTTP/1.1", "GET x HTTP/1.1", "GET / HTTP/3", "GET /  HTTP/1.1", "GET /", "GET / HTTP/1.1 extra", "", "CONNECT /a HTTP/1.1"]]) + "\n"),
    case("malformed-structure", "\n".join([line() + " ", line() + " x", " " + line(), line().replace(" - - ", "  -  - "), line().replace("[", "").replace("]", ""), line(ident="a[b"), line(user="a b"), line(status="2000"), line(status="20"), line(status="600"), line().replace('"', "'")]) + "\n"),
    case("blank-lines", "\n  \n" + line() + "\n\n" + "junk\n"),
    case("big", "\n".join(big_lines) + "\n"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
