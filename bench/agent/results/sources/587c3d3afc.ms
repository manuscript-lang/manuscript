import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Line:
    sku: String
    qty: Int

type Order:
    status: String
    total: Int
    lines: List[Line]

type Store:
    stock: Map[String, Int]
    price: Map[String, Int]
    orders: Map[String, Order]

fn is_digit(v: Int) Bool: v >= 48 and v <= 57

fn sku_ok(text: String) Bool:
    if text.length() == 0: return false

    for v in text.scalar_values():
        if not (is_digit(v) or (v >= 65 and v <= 90) or v == 45): return false
    return true

fn id_ok(text: String) Bool:
    if text.length() == 0: return false

    for v in text.scalar_values():
        if not (is_digit(v) or (v >= 97 and v <= 122) or v == 45): return false
    return true

# Returns the value of a well-formed number in [low, high], or -1 when it is not one.
fn number(text: String, low: Int, high: Int) Int:
    if text.length() == 0 or text.length() > 7: return -1

    var v = 0

    for d in text.scalar_values():
        if not is_digit(d): return -1

        v = v * 10 + d - 48

    if v < low or v > high: return -1

    return v

fn money(cents: Int) String:
    return "{cents / 100}." + (cents % 100).to_string().pad_start(2, "0")

fn stock_cmd(var s: Store, t: List[String]) String:
    if t.length() != 3: return "error: usage"

    let sku = t[1].clone()
    if not sku_ok(sku): return "error: bad sku"

    let qty = number(t[2], 1, 100000)
    if qty < 0: return "error: bad quantity"

    if not s.stock.contains(sku):
        s.stock.add(sku.clone(), 0)
        s.price.add(sku.clone(), 0)

    let now = s.stock.get(sku).get(0) + qty
    s.stock.add(sku.clone(), now)
    return "ok {sku} stock={now}"

fn price_cmd(var s: Store, t: List[String]) String:
    if t.length() != 3: return "error: usage"

    let sku = t[1].clone()
    let cents = number(t[2], 0, 10000000)
    if cents < 0: return "error: bad price"
    if not s.stock.contains(sku): return "error: unknown sku {sku}"

    s.price.add(sku, cents)
    return "ok"

fn order_cmd(var s: Store, t: List[String]) String:
    if t.length() < 3: return "error: usage"

    let id = t[1].clone()
    if not id_ok(id): return "error: bad order id"
    if s.orders.contains(id): return "error: order {id} already exists"

    var lines = List[Line]()

    for i in 2..t.length():
        let parts = t[i].split(":")
        if parts.length() != 2 or not sku_ok(parts[0]): return "error: bad item {t[i]}"

        let qty = number(parts[1], 1, 100000)
        if qty < 0: return "error: bad item {t[i]}"

        lines.append(Line(sku: parts[0].clone(), qty: qty))

    var total = 0

    for i in 0..lines.length():
        let sku = lines[i].sku.clone()
        let qty = lines[i].qty
        for j in 0..i:
            if lines[j].sku == sku: return "error: duplicate sku {sku}"
        if not s.stock.contains(sku): return "error: unknown sku {sku}"

        let have = s.stock.get(sku).get(0)
        if qty > have: return "error: insufficient stock for {sku} (have {have}, need {qty})"

        let cost = qty * s.price.get(sku).get(0)

        if qty >= 10: total += (cost * 90 + 50) / 100
        else: total += cost

    for line in lines:
        s.stock.add(line.sku.clone(), s.stock.get(line.sku).get(0) - line.qty)
    s.orders.add(id.clone(), Order(status: "placed", total: total, lines: lines))
    return "ok {id} total={money(total)}"

fn cancel_cmd(var s: Store, t: List[String]) String:
    if t.length() != 2: return "error: usage"

    let id = t[1].clone()

    if let o = s.orders.get(id):
        if o.status == "shipped": return "error: order {id} already shipped"
        if o.status == "cancelled": return "error: order {id} already cancelled"

        let total = o.total
        let lines = o.lines.clone()
        for line in lines:
            s.stock.add(line.sku.clone(), s.stock.get(line.sku).get(0) + line.qty)
        s.orders.add(id.clone(), Order(status: "cancelled", total: total, lines: lines))
        return "ok"

    return "error: unknown order {id}"

fn ship_cmd(var s: Store, t: List[String]) String:
    if t.length() != 2: return "error: usage"

    let id = t[1].clone()

    if let o = s.orders.get(id):
        if o.status == "shipped": return "error: order {id} already shipped"
        if o.status == "cancelled": return "error: order {id} is cancelled"

        let total = o.total
        let lines = o.lines.clone()
        s.orders.add(id.clone(), Order(status: "shipped", total: total, lines: lines))
        return "ok"

    return "error: unknown order {id}"

fn report_cmd(var s: Store, t: List[String]) String:
    if t.length() != 1: return "error: usage"

    var lines = List[String]()
    var reserved = Map[String, Int]()
    var placed = 0
    var shipped = 0
    var cancelled = 0
    var revenue = 0

    for o in s.orders.values():
        if o.status == "placed":
            placed += 1
            for line in o.lines:
                reserved.add(line.sku.clone(), reserved.get(line.sku).get(0) + line.qty)
        else if o.status == "shipped":
            shipped += 1
            revenue += o.total
        else:
            cancelled += 1

    for sku in s.stock.keys().sorted():
        let stock = s.stock.get(sku).get(0)
        let price = money(s.price.get(sku).get(0))
        lines.append(
            "{sku} stock={stock} price={price} reserved={reserved.get(sku).get(0)}"
        )

    lines.append("orders placed={placed} shipped={shipped} cancelled={cancelled}")
    lines.append("revenue={money(revenue)}")
    return lines.join("\n")

fn run(var s: Store, t: List[String]) String:
    let name = t[0].clone()

    if name == "stock": return stock_cmd(var s, t)
    else if name == "price": return price_cmd(var s, t)
    else if name == "order": return order_cmd(var s, t)
    else if name == "cancel": return cancel_cmd(var s, t)
    else if name == "ship": return ship_cmd(var s, t)
    else if name == "report": return report_cmd(var s, t)

    return "error: unknown command"

export fn main() Int:
    var s = Store(
        stock: Map[String, Int](), price: Map[String, Int](),
        orders: Map[String, Order]()
    )
    var out = stdout()

    for line in read_lines(stdin()).get():
        let t = line.split(" ")
        if t.all(fn x: x == ""): continue

        out.write(run(var s, t) + "\n").get()

    return 0
