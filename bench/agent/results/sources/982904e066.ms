import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Item:
    sku: String
    qty: Int

type Order:
    state: String
    total: Int
    items: List[Item]

type Shop:
    stock: Map[String, Int]
    price: Map[String, Int]
    orders: Map[String, Order]

# Returns the value of a 1-to-7 digit number, or -1 when the text is malformed.
fn number(text: String) Int:
    if text.is_empty() or text.length() > 7: return -1
    if not text.scalar_values().all(fn c: c >= 48 and c <= 57): return -1

    return text.parse_int().get(-1)

fn valid_qty(text: String) Bool:
    let q = number(text)
    return q >= 1 and q <= 100000

fn is_sku(text: String) Bool:
    return (
        not text.is_empty()
        and text.scalar_values().all(
            fn c: (
                (c >= 65 and c <= 90)
                or (c >= 48 and c <= 57)
                or c == 45
            )
        )
    )

fn is_id(text: String) Bool:
    return (
        not text.is_empty()
        and text.scalar_values().all(
            fn c: (
                (c >= 97 and c <= 122)
                or (c >= 48 and c <= 57)
                or c == 45
            )
        )
    )

fn money(cents: Int) String:
    let frac = "{cents % 100}"
    return "{cents / 100}.{frac.pad_start(2, "0")}"

# Line cost in cents; quantities of 10 or more get a 10% discount, rounded half up.
fn line_cost(qty: Int, base: Int) Int:
    let raw = qty * base
    if qty >= 10: return (raw * 90 + 50) / 100

    return raw

fn valid_item(token: String) Bool:
    let pair = token.split(":")
    return pair.length() == 2 and is_sku(pair[0]) and valid_qty(pair[1])

fn arity_ok(name: String, count: Int) Bool:
    if name == "order": return count >= 3
    if name == "stock" or name == "price": return count == 3
    if name == "report": return count == 1

    return count == 2

fn stock_cmd(var shop: Shop, sku: String, text: String) List[String]:
    if not is_sku(sku): return ["error: bad sku"]

    let qty = number(text)
    if qty < 1 or qty > 100000: return ["error: bad quantity"]

    let now = shop.stock.get(sku).get(0) + qty
    shop.stock.add(sku.clone(), now)
    if not shop.price.contains(sku): shop.price.add(sku.clone(), 0)
    return ["ok {sku} stock={now}"]

fn price_cmd(var shop: Shop, sku: String, text: String) List[String]:
    let cents = number(text)
    if cents < 0 or cents > 10000000: return ["error: bad price"]
    if not shop.price.contains(sku): return ["error: unknown sku {sku}"]

    shop.price.add(sku.clone(), cents)
    return ["ok"]

fn order_cmd(var shop: Shop, id: String, tokens: List[String]) List[String]:
    if not is_id(id): return ["error: bad order id"]

    for token in tokens:
        if not valid_item(token): return ["error: bad item {token}"]
    if shop.orders.contains(id): return ["error: order {id} already exists"]

    var seen = Set[String]()
    var items = List[Item]()

    for token in tokens:
        let pair = token.split(":")
        let sku = pair[0]
        let qty = number(pair[1])
        if seen.contains(sku): return ["error: duplicate sku {sku}"]
        if not shop.price.contains(sku): return ["error: unknown sku {sku}"]

        let have = shop.stock.get(sku).get(0)
        if qty > have: return [
            "error: insufficient stock for {sku} (have {have}, need {qty})"
        ]

        seen.add(sku.clone())
        items.append(Item(sku: sku.clone(), qty: qty))

    var total = 0

    for item in items:
        shop.stock.add(item.sku.clone(), shop.stock.get(item.sku).get(0) - item.qty)
        total += line_cost(item.qty, shop.price.get(item.sku).get(0))

    shop.orders.add(id.clone(), Order(state: "placed", total: total, items: items))
    return ["ok {id} total={money(total)}"]

fn cancel_cmd(var shop: Shop, id: String) List[String]:
    if let order = shop.orders.get(id):
        if order.state == "shipped": return ["error: order {id} already shipped"]
        if order.state == "cancelled": return ["error: order {id} already cancelled"]

        let items = order.items.clone()
        let total = order.total
        for item in items:
            shop.stock.add(item.sku.clone(), shop.stock.get(item.sku).get(0) + item.qty)
        shop.orders.add(
            id.clone(), Order(state: "cancelled", total: total, items: items)
        )
        return ["ok"]

    return ["error: unknown order {id}"]

fn ship_cmd(var shop: Shop, id: String) List[String]:
    if let order = shop.orders.get(id):
        if order.state == "shipped": return ["error: order {id} already shipped"]
        if order.state == "cancelled": return ["error: order {id} is cancelled"]

        let items = order.items.clone()
        let total = order.total
        shop.orders.add(id.clone(), Order(state: "shipped", total: total, items: items))
        return ["ok"]

    return ["error: unknown order {id}"]

fn report(shop: Shop) List[String]:
    var lines = List[String]()

    for sku in shop.price.keys().sorted():
        var reserved = 0
        for entry in shop.orders.entries():
            if entry.value.state == "placed":
                for item in entry.value.items:
                    if item.sku == sku: reserved += item.qty

        let stock = shop.stock.get(sku).get(0)
        let price = shop.price.get(sku).get(0)
        lines.append("{sku} stock={stock} price={money(price)} reserved={reserved}")

    var placed = 0
    var shipped = 0
    var cancelled = 0
    var revenue = 0

    for entry in shop.orders.entries():
        let state = entry.value.state
        if state == "placed": placed += 1

        if state == "shipped":
            shipped += 1
            revenue += entry.value.total

        if state == "cancelled": cancelled += 1

    lines.append("orders placed={placed} shipped={shipped} cancelled={cancelled}")
    lines.append("revenue={money(revenue)}")
    return lines

fn run(var shop: Shop, parts: List[String]) List[String]:
    let name = parts[0]
    if not ["stock", "price", "order", "cancel", "ship", "report"].contains(name): return [
        "error: unknown command"
    ]
    if not arity_ok(name, parts.length()): return ["error: usage"]
    if name == "stock": return stock_cmd(var shop, parts[1].clone(), parts[2].clone())
    if name == "price": return price_cmd(var shop, parts[1].clone(), parts[2].clone())

    if name == "order":
        var tokens = List[String]()
        for i in 2..parts.length():
            tokens.append(parts[i].clone())
        return order_cmd(var shop, parts[1].clone(), tokens)

    if name == "cancel": return cancel_cmd(var shop, parts[1].clone())
    if name == "ship": return ship_cmd(var shop, parts[1].clone())

    return report(shop)

fn blank(parts: List[String]) Bool:
    return parts.all(fn p: p.is_empty())

export fn main() Int:
    var shop = Shop(
        stock: Map[String, Int](), price: Map[String, Int](),
        orders: Map[String, Order]()
    )
    var out = stdout()

    for line in read_lines(stdin()).get():
        let parts = line.split(" ")
        if not blank(parts):
            for text in run(var shop, parts):
                out.write("{text}\n").get()

    return 0
