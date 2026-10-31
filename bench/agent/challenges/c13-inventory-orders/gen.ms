# Generator for c13-inventory-orders. Deterministic; run: ms run bench/agent/gen.ms -- c13
import GenCase, make_case, write_cases from "../../lib/gen.ms"
import seeded from "../../lib/pyrandom.ms"
import full_match from "../../lib/text.ms"

let SKU = "[A-Z0-9-]+"
let OID = "[a-z0-9-]+"
let NUM = "[0-9]\{1,7\}"

fn money(c: Int) String: "{c / 100}.{"{c % 100}".pad_start(2, "0")}"

fn qty_ok(s: String) Bool: full_match(NUM, s) and s.parse_int().get(0) >= 1 and s.parse_int().get(0) <= 100000

fn arity(c: String) Int:
    if c == "stock" or c == "price": return 3
    if c == "cancel" or c == "ship": return 2
    if c == "report": return 1
    return 0

type Item:
    sku: String
    qty: Int

fn solve(s: String) String:
    var lines = s.split("\n")
    if not lines.is_empty() and lines[lines.length() - 1] == "": lines.pop()
    var stock = Map[String, Int]()
    var price = Map[String, Int]()
    var skus = List[String]()
    var order_ids = List[String]()
    var order_items = Map[String, List[Item]]()
    var order_status = Map[String, String]()
    var order_total = Map[String, Int]()
    var out = List[String]()
    for l in lines:
        if l.replace(" ", "") == "": continue

        let t = l.split(" ")
        let c = t[0].clone()
        if c != "order" and arity(c) == 0:
            out.append("error: unknown command")
            continue

        if (c == "order" and t.length() < 3) or (c != "order" and t.length() != arity(c)):
            out.append("error: usage")
            continue

        if c == "stock":
            if not full_match(SKU, t[1]):
                out.append("error: bad sku")
                continue

            if not qty_ok(t[2]):
                out.append("error: bad quantity")
                continue

            if not stock.contains(t[1]):
                skus.append(t[1].clone())
                price[t[1].clone()] = 0
            stock[t[1].clone()] = stock.get_or(t[1], 0) + t[2].parse_int().get(0)
            out.append("ok {t[1]} stock={stock.get_or(t[1], 0)}")
        else if c == "price":
            if not (full_match(NUM, t[2]) and t[2].parse_int().get(0) <= 10000000):
                out.append("error: bad price")
                continue

            if not stock.contains(t[1]):
                out.append("error: unknown sku {t[1]}")
                continue

            price[t[1].clone()] = t[2].parse_int().get(0)
            out.append("ok")
        else if c == "order":
            let oid = t[1].clone()
            if not full_match(OID, oid):
                out.append("error: bad order id")
                continue

            if order_status.contains(oid):
                out.append("error: order {oid} already exists")
                continue

            var items = List[Item]()
            var bad = ""
            for tok in t.slice(2, t.length()).get([]):
                let p = tok.split(":")
                if p.length() != 2 or not full_match(SKU, p[0]) or not qty_ok(p[1]):
                    bad = tok.clone()
                    break

                items.append(Item(p[0].clone(), p[1].parse_int().get(0)))
            if bad != "":
                out.append("error: bad item {bad}")
                continue

            var err = ""
            var seen = Set[String]()
            for item in items:
                if seen.contains(item.sku):
                    err = "error: duplicate sku {item.sku}"
                else if not stock.contains(item.sku):
                    err = "error: unknown sku {item.sku}"
                else if item.qty > stock.get_or(item.sku, 0):
                    err = "error: insufficient stock for {item.sku} (have {stock.get_or(item.sku, 0)}, need {item.qty})"
                if err != "": break

                seen.add(item.sku.clone())
            if err != "":
                out.append(err)
                continue

            var total = 0
            for item in items:
                stock[item.sku.clone()] = stock.get_or(item.sku, 0) - item.qty
                let p = price.get_or(item.sku, 0)
                total += if item.qty >= 10: (item.qty * p * 90 + 50) / 100 else: item.qty * p
            order_ids.append(oid.clone())
            order_items[oid.clone()] = items.clone()
            order_status[oid.clone()] = "placed"
            order_total[oid.clone()] = total
            out.append("ok {oid} total={money(total)}")
        else if c == "cancel" or c == "ship":
            if not order_status.contains(t[1]):
                out.append("error: unknown order {t[1]}")
                continue

            let st = order_status.get_or(t[1], "")
            if c == "cancel":
                if st == "placed":
                    for item in order_items.get_or(t[1], []):
                        stock[item.sku.clone()] = stock.get_or(item.sku, 0) + item.qty
                    order_status[t[1].clone()] = "cancelled"
                    out.append("ok")
                else:
                    out.append("error: order {t[1]} already {st}")
            else if st == "placed":
                order_status[t[1].clone()] = "shipped"
                out.append("ok")
            else if st == "shipped":
                out.append("error: order {t[1]} already shipped")
            else:
                out.append("error: order {t[1]} is cancelled")
        else:
            var reserved = Map[String, Int]()
            for oid in order_ids:
                if order_status.get_or(oid, "") == "placed":
                    for item in order_items.get_or(oid, []):
                        reserved[item.sku.clone()] = reserved.get_or(item.sku, 0) + item.qty
            for sku in skus.sorted():
                out.append("{sku} stock={stock.get_or(sku, 0)} price={money(price.get_or(sku, 0))} reserved={reserved.get_or(sku, 0)}")
            let placed = order_ids.count(fn o: order_status.get_or(o, "") == "placed")
            let shipped = order_ids.count(fn o: order_status.get_or(o, "") == "shipped")
            let cancelled = order_ids.count(fn o: order_status.get_or(o, "") == "cancelled")
            out.append("orders placed={placed} shipped={shipped} cancelled={cancelled}")
            let revenue = order_ids.filter(fn o: order_status.get_or(o, "") == "shipped").map(fn o: order_total.get_or(o, 0)).sum()
            out.append("revenue={money(revenue)}")
    return out.map(fn x: x + "\n").join("")

fn mk(name: String, s: String) GenCase: make_case(name, s, solve(s))

export fn gen_c13() Unit:
    var rnd = seeded(13)
    let skus = ["A1", "B-2", "WIDGET", "GADGET-2", "Z9", "KNOB", "BOLT-10", "NUT"]
    var big = List[String]()
    for k in skus: big.append("stock {k} {rnd.randint(50, 400)}")
    for k in skus: big.append("price {k} {rnd.randint(1, 5000)}")
    var n = 0
    for _i in 0..900:
        let r = rnd.random()
        if r < 0.45:
            n += 1
            let count = rnd.randint(1, 3)
            var parts = List[String]()
            for k in rnd.sample(skus, count): parts.append("{k}:{["1", "2", "3", "5", "9", "10", "12", "25"].get(rnd.below(8))}")
            big.append("order o{n} {parts.join(" ")}")
        else if r < 0.6:
            big.append("cancel o{rnd.randint(1, if n > 1: n else: 1)}")
        else if r < 0.8:
            big.append("ship o{rnd.randint(1, if n > 1: n else: 1)}")
        else if r < 0.9:
            let k = rnd.choice(skus)
            big.append("stock {k} {rnd.randint(1, 100)}")
        else if r < 0.95:
            let k = rnd.choice(skus)
            big.append("price {k} {rnd.randint(1, 5000)}")
        else:
            big.append("report")
    big.append("report")
    let examples = [
        mk("basic", "stock WIDGET 100\nstock GADGET-2 5\nprice WIDGET 250\nprice GADGET-2 1999\norder o1 WIDGET:10 GADGET-2:2\norder o2 GADGET-2:4\nship o1\ncancel o1\nreport\n"),
        mk("cancel-restores", "stock A 5\nprice A 100\norder x A:5\norder y A:1\ncancel x\norder y A:1\nreport\n")
    ]
    let hidden = examples.concat([
        mk("stock-errors", "stock\nstock A\nstock a 5\nstock A 0\nstock A 100001\nstock A 1x\nstock A 00000005\nstock A -1\nstock A 5 6\nstock A- 1\nstock A_B 1\nstock A 100000\nstock A 100000\n"),
        mk("price-errors", "price A 1\nstock A 1\nprice A -1\nprice A 10000001\nprice A 10000000\nprice a 1\nprice A x\nprice A 0\nreport\n"),
        mk("discount-rounding", "stock A 100\nprice A 5\norder o1 A:10\norder o2 A:11\nprice A 1\norder o3 A:10\norder o4 A:9\nprice A 3\norder o5 A:10\nreport\n"),
        mk("order-errors", "stock A 5\nprice A 100\norder\norder o1\norder O1 A:1\norder o_1 A:1\norder o1 A\norder o1 A:1:2\norder o1 a:1\norder o1 A:0\norder o1 A:x\norder o1 A:1 B:x\norder o1 B:1 A:x\norder o1 B:1\norder o1 A:6\norder o1 A:3 A:1\norder o1 A:3 B:1 A:1\norder o1 A:1\norder o1 A:1\n"),
        mk("all-or-nothing", "stock A 5\nstock B 5\nprice A 100\nprice B 200\norder o1 A:3 B:9\nreport\norder o1 A:3 B:2\nreport\n"),
        mk("duplicate-vs-stock", "stock A 5\norder o1 A:9 A:1\norder o2 A:1 A:9\norder o3 A:5 A:5\nreport\n"),
        mk("cancelled-id-reuse", "stock A 5\norder o1 A:1\ncancel o1\norder o1 A:1\n"),
        mk("cancel-ship-states", "stock A 9\nprice A 10\norder o1 A:1\norder o2 A:1\norder o3 A:1\nship o1\nship o1\ncancel o1\ncancel o2\ncancel o2\nship o2\nship o3\nship o9\ncancel o9\ncancel\nship o1 o2\nreport\n"),
        mk("report-reserved-and-revenue", "stock B 20\nstock A 20\nprice A 100\nprice B 250\norder p1 A:2 B:3\norder p2 A:10\norder p3 B:1\nship p3\nship p2\nreport\n"),
        mk("unknown-and-usage", "STOCK A 1\nlist\n\n  \nreport now\nreport\n"),
        mk("price-change-after-order", "stock A 10\nprice A 100\norder o1 A:2\nprice A 999\norder o2 A:2\nship o1\nship o2\nreport\n"),
        mk("big-session", big.join("\n") + "\n")
    ])
    write_cases("c13-inventory-orders", examples, hidden)
