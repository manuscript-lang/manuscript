import json, random, re, pathlib

SKU = re.compile(r"[A-Z0-9-]+")
OID = re.compile(r"[a-z0-9-]+")
NUM = re.compile(r"[0-9]{1,7}")
ARITY = {"stock": 3, "price": 3, "cancel": 2, "ship": 2, "report": 1}

def money(c): return f"{c // 100}.{c % 100:02d}"
def qty_ok(s): return bool(NUM.fullmatch(s)) and 1 <= int(s) <= 100000

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    stock, price, orders, out = {}, {}, {}, []
    for l in lines:
        if l.strip(" ") == "": continue
        t = l.split(" ")
        c = t[0]
        if c != "order" and c not in ARITY: out.append("error: unknown command"); continue
        if (c == "order" and len(t) < 3) or (c != "order" and len(t) != ARITY[c]): out.append("error: usage"); continue
        if c == "stock":
            if not SKU.fullmatch(t[1]): out.append("error: bad sku"); continue
            if not qty_ok(t[2]): out.append("error: bad quantity"); continue
            stock[t[1]] = stock.get(t[1], 0) + int(t[2]); price.setdefault(t[1], 0)
            out.append(f"ok {t[1]} stock={stock[t[1]]}")
        elif c == "price":
            if not (NUM.fullmatch(t[2]) and int(t[2]) <= 10000000): out.append("error: bad price"); continue
            if t[1] not in stock: out.append(f"error: unknown sku {t[1]}"); continue
            price[t[1]] = int(t[2]); out.append("ok")
        elif c == "order":
            oid = t[1]
            if not OID.fullmatch(oid): out.append("error: bad order id"); continue
            if oid in orders: out.append(f"error: order {oid} already exists"); continue
            items, bad = [], None
            for tok in t[2:]:
                p = tok.split(":")
                if len(p) != 2 or not SKU.fullmatch(p[0]) or not qty_ok(p[1]): bad = tok; break
                items.append((p[0], int(p[1])))
            if bad is not None: out.append(f"error: bad item {bad}"); continue
            err, seen = None, set()
            for sku, q in items:
                if sku in seen: err = f"error: duplicate sku {sku}"
                elif sku not in stock: err = f"error: unknown sku {sku}"
                elif q > stock[sku]: err = f"error: insufficient stock for {sku} (have {stock[sku]}, need {q})"
                if err: break
                seen.add(sku)
            if err: out.append(err); continue
            total = 0
            for sku, q in items:
                stock[sku] -= q
                total += (q * price[sku] * 90 + 50) // 100 if q >= 10 else q * price[sku]
            orders[oid] = dict(items=items, status="placed", total=total)
            out.append(f"ok {oid} total={money(total)}")
        elif c in ("cancel", "ship"):
            o = orders.get(t[1])
            if o is None: out.append(f"error: unknown order {t[1]}"); continue
            st = o["status"]
            if c == "cancel":
                if st == "placed":
                    for sku, q in o["items"]: stock[sku] += q
                    o["status"] = "cancelled"; out.append("ok")
                else: out.append(f"error: order {t[1]} already {st}")
            else:
                if st == "placed": o["status"] = "shipped"; out.append("ok")
                elif st == "shipped": out.append(f"error: order {t[1]} already shipped")
                else: out.append(f"error: order {t[1]} is cancelled")
        else:
            reserved = {}
            for o in orders.values():
                if o["status"] == "placed":
                    for sku, q in o["items"]: reserved[sku] = reserved.get(sku, 0) + q
            for sku in sorted(stock, key=lambda x: x.encode()):
                out.append(f"{sku} stock={stock[sku]} price={money(price[sku])} reserved={reserved.get(sku, 0)}")
            cnt = {k: sum(1 for o in orders.values() if o["status"] == k) for k in ("placed", "shipped", "cancelled")}
            out.append(f"orders placed={cnt['placed']} shipped={cnt['shipped']} cancelled={cnt['cancelled']}")
            out.append(f"revenue={money(sum(o['total'] for o in orders.values() if o['status'] == 'shipped'))}")
    return "".join(x + "\n" for x in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(13)
skus = ["A1", "B-2", "WIDGET", "GADGET-2", "Z9", "KNOB", "BOLT-10", "NUT"]
big = [f"stock {k} {rnd.randint(50, 400)}" for k in skus] + [f"price {k} {rnd.randint(1, 5000)}" for k in skus]
n = 0
for _ in range(900):
    r = rnd.random()
    if r < .45:
        n += 1
        items = " ".join(f"{k}:{rnd.choice([1, 2, 3, 5, 9, 10, 12, 25])}" for k in rnd.sample(skus, rnd.randint(1, 3)))
        big.append(f"order o{n} {items}")
    elif r < .6: big.append(f"cancel o{rnd.randint(1, max(n, 1))}")
    elif r < .8: big.append(f"ship o{rnd.randint(1, max(n, 1))}")
    elif r < .9: big.append(f"stock {rnd.choice(skus)} {rnd.randint(1, 100)}")
    elif r < .95: big.append(f"price {rnd.choice(skus)} {rnd.randint(1, 5000)}")
    else: big.append("report")
big.append("report")
examples = [
    case("basic", "stock WIDGET 100\nstock GADGET-2 5\nprice WIDGET 250\nprice GADGET-2 1999\norder o1 WIDGET:10 GADGET-2:2\norder o2 GADGET-2:4\nship o1\ncancel o1\nreport\n"),
    case("cancel-restores", "stock A 5\nprice A 100\norder x A:5\norder y A:1\ncancel x\norder y A:1\nreport\n"),
]
hidden = examples + [
    case("stock-errors", "stock\nstock A\nstock a 5\nstock A 0\nstock A 100001\nstock A 1x\nstock A 00000005\nstock A -1\nstock A 5 6\nstock A- 1\nstock A_B 1\nstock A 100000\nstock A 100000\n"),
    case("price-errors", "price A 1\nstock A 1\nprice A -1\nprice A 10000001\nprice A 10000000\nprice a 1\nprice A x\nprice A 0\nreport\n"),
    case("discount-rounding", "stock A 100\nprice A 5\norder o1 A:10\norder o2 A:11\nprice A 1\norder o3 A:10\norder o4 A:9\nprice A 3\norder o5 A:10\nreport\n"),
    case("order-errors", "stock A 5\nprice A 100\norder\norder o1\norder O1 A:1\norder o_1 A:1\norder o1 A\norder o1 A:1:2\norder o1 a:1\norder o1 A:0\norder o1 A:x\norder o1 A:1 B:x\norder o1 B:1 A:x\norder o1 B:1\norder o1 A:6\norder o1 A:3 A:1\norder o1 A:3 B:1 A:1\norder o1 A:1\norder o1 A:1\n"),
    case("all-or-nothing", "stock A 5\nstock B 5\nprice A 100\nprice B 200\norder o1 A:3 B:9\nreport\norder o1 A:3 B:2\nreport\n"),
    case("duplicate-vs-stock", "stock A 5\norder o1 A:9 A:1\norder o2 A:1 A:9\norder o3 A:5 A:5\nreport\n"),
    case("cancelled-id-reuse", "stock A 5\norder o1 A:1\ncancel o1\norder o1 A:1\n"),
    case("cancel-ship-states", "stock A 9\nprice A 10\norder o1 A:1\norder o2 A:1\norder o3 A:1\nship o1\nship o1\ncancel o1\ncancel o2\ncancel o2\nship o2\nship o3\nship o9\ncancel o9\ncancel\nship o1 o2\nreport\n"),
    case("report-reserved-and-revenue", "stock B 20\nstock A 20\nprice A 100\nprice B 250\norder p1 A:2 B:3\norder p2 A:10\norder p3 B:1\nship p3\nship p2\nreport\n"),
    case("unknown-and-usage", "STOCK A 1\nlist\n\n  \nreport now\nreport\n"),
    case("price-change-after-order", "stock A 10\nprice A 100\norder o1 A:2\nprice A 999\norder o2 A:2\nship o1\nship o2\nreport\n"),
    case("big-session", "\n".join(big) + "\n"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
