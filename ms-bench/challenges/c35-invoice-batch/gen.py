import json, random, pathlib, re

B = " \t"
MONEY = re.compile(r"[0-9]{1,5}(?:\.([0-9]{1,2}))?\Z")
PCT = re.compile(r"([0-9]{1,3})(?:\.([0-9]{1,2}))?\Z")

def money(s):
    m = MONEY.match(s)
    if not m: return None
    whole = s.split(".")[0]
    return int(whole) * 100 + int((m[1] or "").ljust(2, "0") or "0")

def percent_bp(s):
    m = PCT.match(s)
    if not m: return None
    bp = int(m[1]) * 100 + int((m[2] or "").ljust(2, "0") or "0")
    return bp if bp <= 10000 else None

def fmt(c): return f"{c // 100}.{c % 100:02d}"
def rnd_half_up(a, b): return (a + b // 2) // b

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    section, rates, ship, catalog, orders, problems = None, {}, None, {}, [], []
    for n, raw in enumerate(lines, 1):
        l = raw.strip(B)
        if not l or l[0] == "#": continue
        if l[0] == "[":
            section = {"[config]": "c", "[catalog]": "p", "[orders]": "o"}.get(l)
            if section is None: problems.append((n, "unknown section"))
            continue
        if section == "c":
            t = re.split(r"[ \t]+", l)
            if t[0] == "tax" and len(t) == 3 and percent_bp(t[2]) is not None: rates[t[1]] = percent_bp(t[2])
            elif t[0] == "shipping" and len(t) == 3 and money(t[1]) is not None and money(t[2]) is not None: ship = (money(t[1]), money(t[2]))
            else: problems.append((n, "bad config"))
        elif section == "p":
            p = [x.strip(B) for x in l.split("|")]
            if len(p) != 4 or not p[0] or " " in p[0] or "\t" in p[0] or not p[1] or not p[3] or money(p[2]) is None:
                problems.append((n, "bad product")); continue
            if p[0] in catalog: problems.append((n, "duplicate sku")); continue
            catalog[p[0]] = (p[1], money(p[2]), p[3])
        elif section == "o":
            p = [x.strip(B) for x in l.split("|")]
            if len(p) not in (3, 4) or not p[0]: problems.append((n, "bad order")); continue
            if not re.fullmatch(r"[0-9]{1,4}", p[2]) or int(p[2]) < 1: problems.append((n, "bad quantity")); continue
            pct = 0
            if len(p) == 4:
                if not re.fullmatch(r"[0-9]{1,3}", p[3]) or int(p[3]) > 100: problems.append((n, "bad discount")); continue
                pct = int(p[3])
            if p[1] not in catalog: problems.append((n, "unknown sku")); continue
            orders.append((p[0], p[1], int(p[2]), pct))
    inv = {}
    for cust, sku, qty, pct in orders:
        name, price, cls = catalog[sku]
        gross = price * qty
        disc = rnd_half_up(gross * pct, 100)
        net = gross - disc
        tax = rnd_half_up(net * rates.get(cls, 0), 10000)
        inv.setdefault(cust, []).append((sku, name, qty, price, net, disc, tax))
    out, grand = [], 0
    for cust in sorted(inv):
        out.append(f"INVOICE {cust}")
        sub = tax = 0
        for sku, name, qty, price, net, disc, t in inv[cust]:
            out.append(f"  {sku} {name} x{qty} @ {fmt(price)} = {fmt(net)}" + (f" (-{fmt(disc)} discount)" if disc > 0 else ""))
            sub += net; tax += t
        sh = ship[0] if ship and sub < ship[1] else 0
        total = sub + tax + sh
        grand += total
        out += [f"  subtotal {fmt(sub)}", f"  tax {fmt(tax)}", f"  shipping {fmt(sh)}", f"  total {fmt(total)}"]
    out.append(f"summary: invoices={len(inv)} grand_total={fmt(grand)} problems={len(problems)}")
    if problems: out += ["problems:"] + [f"  line {n}: {m}" for n, m in problems]
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(35)
CFG = "[config]\ntax A 20\ntax B 7.5\ntax C 0.25\ntax Z 100\nshipping 4.99 50\n"
def rand_catalog(n):
    ls = ["[catalog]"]
    for i in range(n):
        price = rnd.choice([f"{rnd.randint(0, 999)}.{rnd.randint(0, 99):02d}", str(rnd.randint(1, 500)), f"{rnd.randint(0, 99999)}.{rnd.randint(0, 9)}", "0.05", "0.01", "0.99"])
        ls.append(f"sku{i}|Product {i}{' deluxe' if i % 3 == 0 else ''}|{price}|{rnd.choice('ABCZQ')}")
    return "\n".join(ls) + "\n"
def rand_orders(n, nsku, ncust, noise=.08):
    ls = ["[orders]"]
    for _ in range(n):
        if rnd.random() < noise:
            ls.append(rnd.choice(["", "# c", "ann|sku0", "|sku0|1", "ann|sku0|0", "ann|sku0|10000", "ann|sku0|1|101", "ann|sku0|1|x", "ann|nope|1", "ann|sku0|1|5|extra", "ann|sku0|-1", "ann|sku0|1.5", "ann|sku0|1|10.5"]))
            continue
        c = rnd.choice(["ann", "bob", "Cy", "dee", "eve", "ann ", "zed"][:ncust])
        l = f"{c}|sku{rnd.randrange(nsku)}|{rnd.choice([1, 1, 2, 3, 5, 10, 25, 250, 9999])}"
        if rnd.random() < .4: l += f"|{rnd.choice([0, 5, 10, 15, 33, 50, 100])}"
        ls.append(l)
    return "\n".join(ls) + "\n"
examples = [
    case("basic", "[config]\ntax A 20\ntax B 7.5\nshipping 4.99 50\n[catalog]\npen|Blue pen|1.20|A\npad|Note pad|3.35|B\n[orders]\nann|pen|10\nann|pad|3|10\nbob|pen|1\nbob|ink|2\ncy|pad|x\n"),
    case("rounding", "[config]\ntax A 10\n[catalog]\nc|Candy|0.05|A\n[orders]\nu|c|1|10\nu|c|3|50\nu|c|1\n"),
]
hidden = examples + [
    case("empty", ""),
    case("no-config", "[catalog]\na|Thing|2.50|X\n[orders]\nx|a|2\n"),
    case("shipping-threshold", "[config]\nshipping 5 10\n[catalog]\na|A|5|T\n[orders]\nlow|a|1\nexact|a|2\nhigh|a|3\nfreed|a|3|50\n"),
    case("half-up-rounding", "[config]\ntax R 7.5\ntax S 0.5\n[catalog]\nr|R|0.10|R\ns|S|0.99|S\nt|T|1.01|R\n[orders]\na|r|1\nb|s|1\nc|t|1|50\nd|t|7|15\n"),
    case("config-problems", "[config]\ntax A 20\ntax A 25\ntax B\ntax C 101\ntax D 100.01\ntax E 12.345\nshipping 1\nshipping x 5\nshipping 3 7\nshipping 2.5 100000\nfoo bar\n[catalog]\na|A|10|A\n[orders]\nu|a|4\n"),
    case("catalog-problems", "[catalog]\na|One|1|T\na|Again|2|T\nb two|Bad|1|T\nc|Name|1\nd||1|T\ne|Name|1.234|T\nf|Name|123456|T\ng|Spaced Name here|0.00|T\n [catalog]\n[orders]\nu|g|3\nu|a|1\n"),
    case("order-problems", "[catalog]\na|A|1|T\n[orders]\nu|a|1\n|a|1\nu|a\nu|a|1|5|6\nu|a|0\nu|a|00001\nu|a|10000\nu|a|1|100\nu|a|1|101\nu|a|1|-5\nu|a|1|\nu|zzz|1\nu|a| 2 | 5 \n"),
    case("sections-any-order", "[orders]\nu|a|2\n[catalog]\na|A|3|T\n[config]\ntax T 10\n[orders]\nv|a|1\n[bogus]\nw|a|1\n[orders]\nw|a|1\n"),
    case("whitespace", "  [config]  \n\ttax\tA\t  50 \n[catalog]\n  a  |  Spaced name  |  1.5  |  A \n[orders]\n  Mr X  |  a  |  003  |  010  \n"),
    case("customers-sorted", "[catalog]\na|A|1|T\n[orders]\nbob|a|1\nBob|a|1\nalice|a|1\nAlice|a|1\n_x|a|1\n"),
    case("random-small", CFG + rand_catalog(6) + rand_orders(30, 6, 3)),
    case("random-mid", CFG + rand_catalog(40) + rand_orders(500, 40, 6)),
    case("random-large", CFG + rand_catalog(120) + rand_orders(4000, 120, 7, .04)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
