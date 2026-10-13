import json, random, re, pathlib, datetime

def valid_date(s):
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", s): return None
    try: d = datetime.date(int(s[:4]), int(s[5:7]), int(s[8:]))
    except ValueError: return None
    return d if 1900 <= d.year <= 2100 else None

def split_csv(line):
    fields, i, n = [], 0, len(line)
    while True:
        if i < n and line[i] == '"':
            i += 1; buf = []
            while True:
                if i >= n: return None
                if line[i] == '"':
                    if line[i + 1:i + 2] == '"': buf.append('"'); i += 2; continue
                    i += 1; break
                buf.append(line[i]); i += 1
            fields.append("".join(buf))
            if i < n and line[i] != ",": return None
        else:
            j = line.find(",", i)
            if j < 0: j = n
            f = line[i:j]
            if '"' in f: return None
            fields.append(f); i = j
        if i >= n: return fields
        i += 1   # skip comma
        if i >= n: fields.append(""); return fields

def money(c): return f"{c // 100}.{c % 100:02d}"

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    lines += [""] * (3 - len(lines))
    m = re.fullmatch(r"tax_rate=([0-9]{1,3})(?:\.([0-9]{1,2}))?", lines[0])
    bp = None
    if m:
        bp = int(m.group(1)) * 100 + int((m.group(2) or "0").ljust(2, "0"))
        if bp > 10000: bp = None
    if bp is None: return "error: bad tax_rate\n"
    asof = valid_date(lines[1][len("as_of="):]) if lines[1].startswith("as_of=") else None
    if asof is None: return "error: bad as_of\n"
    if lines[2] != "invoice,date,customer,sku,qty,unit_price,discount_pct": return "error: bad header\n"
    out, inv = [], {}
    for n, l in enumerate(lines[3:], 4):
        if l.strip(" ") == "": continue
        f = split_csv(l)
        if f is None or len(f) != 7: out.append(f"rejected line {n}: malformed row"); continue
        iid, date, cust, sku, qty, price, disc = f
        d = valid_date(date)
        if iid == "": r = "empty invoice id"
        elif d is None: r = "bad date"
        elif cust == "": r = "empty customer"
        elif sku == "": r = "empty sku"
        elif not re.fullmatch(r"[0-9]{1,5}", qty) or not 1 <= int(qty) <= 10000: r = "bad qty"
        elif not re.fullmatch(r"[0-9]{1,7}(\.[0-9]{1,2})?", price): r = "bad price"
        elif not re.fullmatch(r"[0-9]{1,3}", disc) or int(disc) > 100: r = "bad discount"
        elif iid in inv and (inv[iid]["date"] != date or inv[iid]["cust"] != cust): r = "conflicting invoice header"
        else: r = None
        if r: out.append(f"rejected line {n}: {r}"); continue
        w, _, fr = price.partition(".")
        cents = int(w) * 100 + int(fr.ljust(2, "0")) if fr else int(w) * 100
        net = (int(qty) * cents * (100 - int(disc)) + 50) // 100
        e = inv.setdefault(iid, {"date": date, "d": d, "cust": cust, "items": 0, "sub": 0})
        e["items"] += 1; e["sub"] += net
    custs, grand = {}, 0
    for iid in sorted(inv, key=lambda k: k.encode()):
        e = inv[iid]
        tax = (e["sub"] * bp + 5000) // 10000
        total = e["sub"] + tax
        due = e["d"] + datetime.timedelta(days=30)
        late = (asof - due).days
        status = f"OVERDUE {late} days" if late > 0 else "OPEN"
        out.append(f"invoice {iid} | {e['date']} | {e['cust']} | items={e['items']} | subtotal={money(e['sub'])} | tax={money(tax)} | total={money(total)} | due={due.isoformat()} | {status}")
        c = custs.setdefault(e["cust"], [0, 0]); c[0] += 1; c[1] += total
        grand += total
    for name in sorted(custs, key=lambda k: k.encode()):
        out.append(f"customer {name} | invoices={custs[name][0]} | total={money(custs[name][1])}")
    rej = sum(1 for x in out if x.startswith("rejected line"))
    out.append(f"summary | invoices={len(inv)} | rejected={rej} | total={money(grand)}")
    return "".join(x + "\n" for x in out)

HDR = "invoice,date,customer,sku,qty,unit_price,discount_pct"
def doc(rows, rate="8.25", asof="2024-03-15"): return f"tax_rate={rate}\nas_of={asof}\n{HDR}\n" + "".join(r + "\n" for r in rows)
def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(19)
custs = ["Acme", "Zed", "Bob's Pizza", '"Quote ""Co"""', "\"Last, First\"", "café"]
big_rows = []
for k in range(300):
    iid = f"INV-{rnd.randint(1, 60):03d}"
    dt = datetime.date(2023, 11, 1) + datetime.timedelta(days=hash(iid) % 1 + (int(iid[4:]) * 3) % 150)
    c = custs[int(iid[4:]) % len(custs)]
    big_rows.append(f"{iid},{dt.isoformat()},{c},SKU{rnd.randint(1, 20)},{rnd.randint(1, 50)},{rnd.randint(0, 500)}.{rnd.randint(0, 99):02d},{rnd.choice([0, 0, 5, 10, 15, 33])}")
big_rows += ["bad row", "INV-999,2024-13-01,X,S,1,1,0", "INV-998,2024-01-01,X,S,0,1,0"]
examples = [
    case("basic", doc(['INV-001,2024-01-15,"Acme, Inc.",WIDGET,3,19.99,10', 'INV-001,2024-01-15,"Acme, Inc.",GADGET,1,5.00,0', "INV-002,2024-03-10,Zed,WIDGET,2,19.99,0", "INV-002,2024-03-11,Zed,WIDGET,2,19.99,0", "INV-003,2024-02-30,Zed,WIDGET,1,1,0"])),
    case("only-header", doc([])),
]
hidden = examples + [
    case("rounding", doc(["A,2024-03-01,X,S,1,0.05,50", "B,2024-03-01,X,S,1,0.01,50", "C,2024-03-01,X,S,3,0.33,0"], rate="10")),
    case("tax-rounding", doc(["A,2024-03-01,X,S,1,0.06,0", "B,2024-03-01,X,S,1,0.05,0", "C,2024-03-01,X,S,7,1.50,0"], rate="5.5")),
    case("quoting", doc(['I1,2024-03-01,"Say ""hi"", ok",S,1,10,0', 'I2,2024-03-01,"a""b",S,1,10,0', 'I3,2024-03-01,"x"y,S,1,10,0', 'I4,2024-03-01,x"y,S,1,10,0', '"I5",2024-03-01,plain,"S,1",2,3.5,0', 'I6,2024-03-01,"unterminated,S,1,1,0'])),
    case("leap-and-year-end", doc(["L,2024-02-29,X,S,1,1,0", "M,2023-02-29,X,S,1,1,0", "Y,2023-12-15,X,S,1,1,0", "C,1900-02-29,X,S,1,1,0", "D,2000-02-29,X,S,1,1,0"], asof="2024-02-01")),
    case("overdue-boundary", doc(["A,2024-02-14,X,S,1,10,0", "B,2024-02-13,X,S,1,10,0", "C,2024-02-15,X,S,1,10,0"], asof="2024-03-15")),
    case("check-order", doc([",bad,,,x,y,z", "I,bad,,,x,y,z", "I,2024-03-01,,,x,y,z", "I,2024-03-01,C,,x,y,z", "I,2024-03-01,C,S,x,y,z", "I,2024-03-01,C,S,1,y,z", "I,2024-03-01,C,S,1,1,z", "I,2024-03-01,C,S,1,1,0"])),
    case("bad-values", doc(["I,2024-03-01,C,S,0,1,0", "I,2024-03-01,C,S,10001,1,0", "I,2024-03-01,C,S,10000,1,0", "I,2024-03-01,C,S,+1,1,0", "J,2024-03-01,C,S,1,1.,0", "J,2024-03-01,C,S,1,1.234,0", "J,2024-03-01,C,S,1,12345678,0", "J,2024-03-01,C,S,1,-1,0", "K,2024-03-01,C,S,1,1,101", "K,2024-03-01,C,S,1,1,100", "K,2024-03-01,C,S,1,1,-5", "K,2024-3-1,C,S,1,1,0", "K,1899-12-31,C,S,1,1,0", "K,2101-01-01,C,S,1,1,0"])),
    case("conflicts", doc(["A,2024-03-01,X,S,1,1,0", "A,2024-03-02,X,S,1,1,0", "A,2024-03-01,Y,S,1,1,0", "A,2024-03-01,X,T,2,1,0", "B,2024-03-01,x,S,1,1,0", "B,2024-03-01,X,S,1,1,0"])),
    case("customers-case-and-order", doc(["i3,2024-03-01,bob,S,1,1,0", "i1,2024-03-01,Bob,S,1,1,0", "I2,2024-03-01,bob,S,1,2,0", "i2,2024-03-01,Zed,S,1,3,0"])),
    case("blank-lines-and-line-numbers", doc(["", "  ", "A,2024-03-01,X,S,1,1,0", "", "bad"])),
    case("large-amounts", doc(["A,2024-03-01,X,S,10000,9999999.99,0", "A,2024-03-01,X,S,10000,9999999.99,100", "B,2024-03-01,X,S,9999,1234567.89,33"], rate="100")),
    case("bad-tax-rate-1", doc([], rate="100.01")),
    case("bad-as-of", doc([], asof="2024-02-30")),
    case("bad-header", "tax_rate=1\nas_of=2024-01-01\ninvoice,date\nA,2024-01-01,X,S,1,1,0\n"),
    case("big", doc(big_rows)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
