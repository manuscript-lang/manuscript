from "@std/streams.ms" import read_lines
from "@std/io.ms" import stdin, stdout

type Line:
    sku: String
    qty: Int

type Order:
    status: String
    total: Int
    lines: List[Line]

type Shop:
    stock: Map[String, Int] = Map[String, Int]()
    price: Map[String, Int] = Map[String, Int]()
    orders: Map[String, Order] = Map[String, Order]()

def emit(text: String) -> Unit:
    stdout().write(f"{text}\n").get()

def is_upper_digit_dash(value: Int) -> Bool: (
    (value >= 65 and value <= 90)
    or (value >= 48 and value <= 57)
    or value == 45
)

def is_lower_digit_dash(value: Int) -> Bool: (
    (value >= 97 and value <= 122)
    or (value >= 48 and value <= 57)
    or value == 45
)

def is_digit(value: Int) -> Bool: value >= 48 and value <= 57

def is_sku(s: String) -> Bool:
    return not s.is_empty() and s.scalar_values().every(is_upper_digit_dash)

def is_order_id(s: String) -> Bool:
    return not s.is_empty() and s.scalar_values().every(is_lower_digit_dash)

def is_number(s: String) -> Bool:
    return s.length() >= 1 and s.length() <= 7 and s.scalar_values().every(is_digit)

def parse_cents(s: String) -> Optional[Int]:
    if not is_number(s): return none

    let cents = s.parse_int().get()
    if cents > 10000000: return none

    return some(cents)

def parse_qty(s: String) -> Optional[Int]:
    if not is_number(s): return none

    let qty = s.parse_int().get()
    if qty < 1 or qty > 100000: return none

    return some(qty)

def money(cents: Int) -> String:
    let frac = cents % 100
    if frac < 10: return f"{cents / 100}.0{frac}"

    return f"{cents / 100}.{frac}"

def line_cost(qty: Int, price: Int) -> Int:
    if qty >= 10: return (qty * price * 90 + 50) / 100

    return qty * price

def cmd_stock(var shop: Shop, parts: List[String]) -> Unit:
    if parts.length() != 3:
        emit("error: usage")
        return

    let sku = parts[1]

    if not is_sku(sku):
        emit("error: bad sku")
        return

    if let qty = parse_qty(parts[2]):
        let stock = shop.stock.get_or(sku, 0) + qty
        if not shop.stock.contains(sku): shop.price.add(sku, 0)
        shop.stock.add(sku, stock)
        emit(f"ok {sku} stock={stock}")
    else:
        emit("error: bad quantity")

def cmd_price(var shop: Shop, parts: List[String]) -> Unit:
    if parts.length() != 3:
        emit("error: usage")
        return

    if let cents = parse_cents(parts[2]):
        let sku = parts[1]

        if not shop.stock.contains(sku):
            emit(f"error: unknown sku {sku}")
            return

        shop.price.add(sku, cents)
        emit("ok")
    else:
        emit("error: bad price")

def cmd_order(var shop: Shop, parts: List[String]) -> Unit:
    if parts.length() < 3:
        emit("error: usage")
        return

    let id = parts[1]

    if not is_order_id(id):
        emit("error: bad order id")
        return

    var lines = List[Line]()

    for token in parts.slice(2, parts.length()).get():
        let pieces = token.split(":")

        if pieces.length() != 2 or not is_sku(pieces[0]):
            emit(f"error: bad item {token}")
            return

        if let qty = parse_qty(pieces[1]):
            lines.append(Line(sku: pieces[0], qty: qty))
        else:
            emit(f"error: bad item {token}")
            return

    if shop.orders.contains(id):
        emit(f"error: order {id} already exists")
        return

    var seen = Set[String]()
    var total = 0

    for line in lines:
        if seen.contains(line.sku):
            emit(f"error: duplicate sku {line.sku}")
            return

        seen.add(line.sku)

        if not shop.stock.contains(line.sku):
            emit(f"error: unknown sku {line.sku}")
            return

        let stock = shop.stock.get_or(line.sku, 0)

        if line.qty > stock:
            emit(
                f"error: insufficient stock for {line.sku} (have {stock}, need {line.qty})"
            )
            return

        total += line_cost(line.qty, shop.price.get_or(line.sku, 0))

    for line in lines:
        shop.stock.add(line.sku, shop.stock.get_or(line.sku, 0) - line.qty)
    shop.orders.add(id, Order(status: "placed", total: total, lines: lines))
    emit(f"ok {id} total={money(total)}")

def cmd_cancel(var shop: Shop, parts: List[String]) -> Unit:
    if parts.length() != 2:
        emit("error: usage")
        return

    let id = parts[1]

    if not shop.orders.contains(id):
        emit(f"error: unknown order {id}")
        return

    let order = shop.orders.get(id).get()

    if order.status == "shipped":
        emit(f"error: order {id} already shipped")
        return

    if order.status == "cancelled":
        emit(f"error: order {id} already cancelled")
        return

    for line in order.lines:
        shop.stock.add(line.sku, shop.stock.get_or(line.sku, 0) + line.qty)
    (
        shop.orders.add(
            id,
            Order(
                status: "cancelled", total: order.total, lines: order.lines.clone()
            )
        )
    )
    emit("ok")

def cmd_ship(var shop: Shop, parts: List[String]) -> Unit:
    if parts.length() != 2:
        emit("error: usage")
        return

    let id = parts[1]

    if not shop.orders.contains(id):
        emit(f"error: unknown order {id}")
        return

    let order = shop.orders.get(id).get()

    if order.status == "shipped":
        emit(f"error: order {id} already shipped")
        return

    if order.status == "cancelled":
        emit(f"error: order {id} is cancelled")
        return

    (
        shop
        .orders
        .add(
            id,
            Order(
                status: "shipped", total: order.total, lines: order.lines.clone()
            )
        )
    )
    emit("ok")

def cmd_report(var shop: Shop, parts: List[String]) -> Unit:
    if parts.length() != 1:
        emit("error: usage")
        return

    var reserved = Map[String, Int]()
    var placed = 0
    var shipped = 0
    var cancelled = 0
    var revenue = 0

    for order in shop.orders.values():
        if order.status == "placed":
            placed += 1
            for line in order.lines:
                reserved.add(line.sku, reserved.get_or(line.sku, 0) + line.qty)

        if order.status == "shipped":
            shipped += 1
            revenue += order.total

        if order.status == "cancelled":
            cancelled += 1

    for sku in (
        shop
        .stock
        .keys()
        .sorted(lambda (a: String, b: String) -> Int: a.compare(b))
    ):
        let stock = shop.stock.get_or(sku, 0)
        let price = shop.price.get_or(sku, 0)
        emit(
            f"{sku} stock={stock} price={money(price)} reserved={reserved.get_or(sku, 0)}"
        )

    emit(f"orders placed={placed} shipped={shipped} cancelled={cancelled}")
    emit(f"revenue={money(revenue)}")

def run(var shop: Shop, text: String) -> Unit:
    if text.replace(" ", "").is_empty(): return

    let parts = text.split(" ")
    let name = parts[0]

    if name == "stock":
        cmd_stock(var shop, parts)
    elif name == "price":
        cmd_price(var shop, parts)
    elif name == "order":
        cmd_order(var shop, parts)
    elif name == "cancel":
        cmd_cancel(var shop, parts)
    elif name == "ship":
        cmd_ship(var shop, parts)
    elif name == "report":
        cmd_report(var shop, parts)
    else:
        emit("error: unknown command")

export def main() -> Int:
    var shop = Shop()
    for text in read_lines(stdin()).get():
        run(var shop, text)
    return 0
