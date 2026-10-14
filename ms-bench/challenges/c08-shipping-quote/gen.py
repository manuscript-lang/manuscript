import json, random, re, pathlib

HEADER = "order,country,weight_g,service,declared_cents"
Z3 = set("AT BE DE ES FR IE IT NL PT SE".split())
RATES = {1: (499, 120), 2: (899, 180), 3: (1499, 250), 4: (2199, 400)}

def money(c): return f"{c // 100}.{c % 100:02d}"
def zone(c): return 1 if c == "US" else 2 if c in ("CA", "MX") else 3 if c in Z3 else 4

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    if not lines or lines[0] != HEADER: return "error: bad header\n"
    out, seen = [], set()
    stats = {k: [0, 0] for k in ("standard", "express", "overnight")}
    rejected = 0
    for n, l in enumerate(lines[1:], 2):
        if l.strip(" ") == "": continue
        f = l.split(",")
        why = None
        if len(f) != 5: why = "malformed row"
        else:
            oid, cc, w, svc, dec = f
            if not re.fullmatch(r"[A-Za-z0-9-]+", oid): why = "bad order"
            elif not re.fullmatch(r"[A-Z]{2}", cc): why = "bad country"
            elif not (re.fullmatch(r"[0-9]{1,5}", w) and 1 <= int(w) <= 30000): why = "bad weight"
            elif svc not in stats: why = "bad service"
            elif not (re.fullmatch(r"[0-9]{1,8}", dec) and int(dec) <= 10000000): why = "bad declared"
            elif oid in seen: why = "duplicate order"
            elif svc == "overnight" and zone(cc) != 1: why = "overnight unavailable"
        if why:
            out.append(f"line {n}: rejected: {why}"); rejected += 1; continue
        seen.add(oid)
        w, dec, z = int(w), int(dec), zone(cc)
        band = (w + 499) // 500
        start, step = RATES[z]
        rate = start + step * (band - 1)
        base = rate if svc == "standard" else (rate * 3 + 1) // 2 if svc == "express" else rate * 3
        if svc == "standard" and z == 1 and w <= 2000 and dec >= 5000: base = 0
        fuel = (base * 8 + 50) // 100
        ins = 0 if dec <= 10000 else (dec + 50) // 100
        total = base + fuel + ins
        stats[svc][0] += 1; stats[svc][1] += total
        out.append(f"{oid} | zone={z} | band={band} | base={money(base)} | fuel={money(fuel)} | insurance={money(ins)} | total={money(total)}")
    for k, (c, t) in stats.items(): out.append(f"service {k}: orders={c} total={money(t)}")
    out.append(f"summary: orders={sum(c for c, _ in stats.values())} rejected={rejected} total={money(sum(t for _, t in stats.values()))}")
    return "".join(x + "\n" for x in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
def doc(rows): return HEADER + "\n" + "".join(r + "\n" for r in rows)
rnd = random.Random(8)
ccs = ["US", "US", "CA", "MX", "DE", "FR", "SE", "JP", "AU", "BR", "GB", "IN"]
big = []
for i in range(600):
    big.append(f"ORD-{i}{'' if rnd.random() > .02 else 'x y'},{rnd.choice(ccs)},{rnd.randint(1, 30000) if rnd.random() < .7 else rnd.randint(1, 2500)},{rnd.choice(['standard', 'standard', 'express', 'overnight'])},{rnd.choice([0, 100, 5000, 9999, 10000, 10001, 123456, rnd.randint(0, 10000000)])}")
examples = [
    case("basic", doc(["A-1,US,1200,standard,6000", "A-2,DE,2600,express,20000", "A-3,US,100,overnight,0", "A-4,FR,100,overnight,0", "A-5,us,100,standard,0", "A-1,US,100,standard,0", "A-6,JP,30001,standard,0"])),
    case("empty-orders", doc([])),
]
hidden = examples + [
    case("zone-rates", doc([f"Z{i},{c},{w},standard,0" for i, (c, w) in enumerate([("US", 500), ("US", 501), ("CA", 500), ("CA", 1500), ("DE", 1000), ("DE", 30000), ("JP", 1), ("JP", 2500), ("MX", 501), ("ZZ", 7000)])])),
    case("express-rounding", doc(["E1,US,500,express,0", "E2,US,1000,express,0", "E3,CA,500,express,0", "E4,JP,500,express,0", "E5,FR,501,express,0"])),
    case("free-shipping-edges", doc(["F1,US,2000,standard,5000", "F2,US,2001,standard,5000", "F3,US,2000,standard,4999", "F4,US,2000,express,5000", "F5,CA,2000,standard,5000", "F6,US,2000,standard,20000"])),
    case("insurance-rounding", doc(["I1,US,500,standard,10000", "I2,US,500,standard,10001", "I3,US,500,standard,10049", "I4,US,500,standard,10050", "I5,US,500,standard,10000000"])),
    case("fuel-rounding", doc(["R1,US,500,standard,0", "R2,US,1000,standard,0", "R3,JP,500,standard,0", "R4,JP,1500,standard,0"])),
    case("overnight", doc(["N1,US,100,overnight,0", "N2,CA,100,overnight,0", "N3,US,30000,overnight,10000000"])),
    case("reject-reasons", doc(["a,b", "a,US,1,standard,0,x", ",US,1,standard,0", "a b,US,1,standard,0", "o1,USA,1,standard,0", "o2,U1,1,standard,0", "o3,US,0,standard,0", "o4,US,30001,standard,0", "o5,US,0001,standard,0", "o6,US,1,Standard,0", "o7,US,1,standard,", "o8,US,1,standard,10000001", "o9,US,1,standard,-1", "o10,US,1.5,standard,0", "o11,US,123456,standard,0"])),
    case("reject-order-of-checks", doc(["x,xx,0,fast,x", "x,US,0,fast,x", "x,US,5,fast,x", "x,US,5,standard,x", "d,US,5,standard,0", "d,CA,5,overnight,0", "e,CA,5,overnight,0", "e,CA,5,overnight,0"])),
    case("blank-lines-numbering", HEADER + "\n\n  \nq1,US,1,standard,0\n\nbad\n"),
    case("bad-header-1", "order,country\nA,US,1,standard,0\n"),
    case("bad-header-2", ""),
    case("big", doc(big)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
