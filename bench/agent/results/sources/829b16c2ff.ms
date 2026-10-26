from "@std/io.ms" import stdout, stdin
from "@std/streams.ms" import read_lines
from "@std/collections.ms" import range

type Sku:
    stock: Int
    price: Int

type Item:
    sku: String
    qty: Int

type Status:
    case Placed
    case Shipped
    case Cancelled

type Order:
    items: List[Item]
    total: Int
    status: Status

type Shop:
    skus: Map[String, Sku]
    orders: Map[String, Order]

def is_blank(line: String) -> Bool:
    for v in line.scalar_values():
        if v != 32:
            return False
    return True

def valid_sku(text: String) -> Bool:
    if text.length() == 0:
        return False

    for v in text.scalar_values():
        if not ((v >= 65 and v <= 90) or (v >= 48 and v <= 57) or v == 45):
            return False
    return True

def valid_id(text: String) -> Bool:
    if text.length() == 0:
        return False

    for v in text.scalar_values():
        if not ((v >= 97 and v <= 122) or (v >= 48 and v <= 57) or v == 45):
            return False
    return True

def number(text: String) -> Optional[Int]:
    if text.length() < 1 or text.length() > 7:
        return none

    for v in text.scalar_values():
        if v < 48 or v > 57:
            return none
    return text.parse_int()

def quantity(text: String) -> Optional[Int]:
    if let n = number(text):
        if n >= 1 and n <= 100000:
            return some(n)
    return none

def price_cents(text: String) -> Optional[Int]:
    if let n = number(text):
        if n >= 0 and n <= 10000000:
            return some(n)
    return none

def money(cents: Int) -> String:
    let rest = cents % 100
    if rest < 10:
        return f"{cents / 100}.0{rest}"

    return f"{cents / 100}.{rest}"

def label(status: Status) -> String:
    match status:
        case Placed:
            return "placed"
        case Shipped:
            return "shipped"
        case Cancelled:
            return "cancelled"

def parse_item(token: String) -> Optional[Item]:
    let parts = token.split(":")
    if parts.length() != 2:
        return none

    let sku = parts[0]
    if not valid_sku(sku):
        return none
    if let qty = quantity(parts[1]):
        return some(Item(sku: sku, qty: qty))

    return none

def line_cost(item: Item, price: Int) -> Int:
    if item.qty >= 10:
        return (item.qty * price * 90 + 50) / 100

    return item.qty * price

def stock_cmd(var shop: Shop, sku: String, qty_text: String) -> String:
    if not valid_sku(sku):
        return "error: bad sku"

    if let added = quantity(qty_text):
        var current = Sku(stock: 0, price: 0)
        if let known = shop.skus.get(sku):
            current = known
        current.stock += added
        shop.skus.add(sku, current)
        return f"ok {sku} stock={current.stock}"

    return "error: bad quantity"

def price_cmd(var shop: Shop, sku: String, cents_text: String) -> String:
    if let cents = price_cents(cents_text):
        if not shop.skus.contains(sku):
            return f"error: unknown sku {sku}"

        let known = shop.skus.get_or(sku, Sku(stock: 0, price: 0))
        shop.skus.add(sku, Sku(stock: known.stock, price: cents))
        return "ok"

    return "error: bad price"

def order_cmd(var shop: Shop, tokens: List[String]) -> String:
    let id = tokens[1]
    if not valid_id(id):
        return "error: bad order id"

    var items = List[Item]()

    for i in range(2, tokens.length()):
        let token = tokens[i]

        if let item = parse_item(token):
            items.append(item)
        else:
            return f"error: bad item {token}"

    if shop.orders.contains(id):
        return f"error: order {id} already exists"

    var seen = Set[String]()

    for item in items:
        if seen.contains(item.sku):
            return f"error: duplicate sku {item.sku}"

        seen.add(item.sku)

        if let known = shop.skus.get(item.sku):
            if known.stock < item.qty:
                return f"error: insufficient stock for {item.sku} (have {known.stock}, need {item.qty})"
        else:
            return f"error: unknown sku {item.sku}"

    var total = 0

    for item in items:
        let known = shop.skus.get_or(item.sku, Sku(stock: 0, price: 0))
        total += line_cost(item, known.price)
        shop.skus.add(item.sku, Sku(stock: known.stock - item.qty, price: known.price))

    shop.orders.add(id, Order(items: items, total: total, status: Placed))
    return f"ok {id} total={money(total)}"

def cancel_cmd(var shop: Shop, id: String) -> String:
    if let order = shop.orders.get(id).clone():
        match order.status:
            case Placed:
                for item in order.items:
                    let known = shop.skus.get_or(item.sku, Sku(stock: 0, price: 0))
                    shop.skus.add(
                        item.sku,
                        Sku(
                            stock: known.stock + item.qty, price: known.price
                        )
                    )

                shop.orders.add(
                    id,
                    Order(
                        items: order.items.clone(), total: order.total,
                        status: Cancelled
                    )
                )
                return "ok"
            case Shipped:
                return f"error: order {id} already shipped"
            case Cancelled:
                return f"error: order {id} already cancelled"

    return f"error: unknown order {id}"

def ship_cmd(var shop: Shop, id: String) -> String:
    if let order = shop.orders.get(id).clone():
        match order.status:
            case Placed:
                shop.orders.add(
                    id,
                    Order(
                        items: order.items.clone(), total: order.total, status: Shipped
                    )
                )
                return "ok"
            case Shipped:
                return f"error: order {id} already shipped"
            case Cancelled:
                return f"error: order {id} is cancelled"

    return f"error: unknown order {id}"

def report(shop: Shop) -> String:
    var reserved = Map[String, Int]()
    var placed = 0
    var shipped = 0
    var cancelled = 0
    var revenue = 0

    for entry in shop.orders.entries():
        let order = entry.value
        let state = label(order.status)

        if state == "placed":
            placed += 1
            for item in order.items:
                reserved.add(item.sku, reserved.get_or(item.sku, 0) + item.qty)

        if state == "shipped":
            shipped += 1
            revenue += order.total

        if state == "cancelled":
            cancelled += 1

    var lines = List[String]()
    let skus = shop.skus.keys().sorted(lambda a, b: a.compare(b))
    for sku in skus:
        if let known = shop.skus.get(sku):
            lines.append(
                f"{sku} stock={known.stock} price={money(known.price)} reserved={reserved.get_or(sku, 0)}"
            )
    lines.append(f"orders placed={placed} shipped={shipped} cancelled={cancelled}")
    lines.append(f"revenue={money(revenue)}")
    return lines.join("\n")

def handle(var shop: Shop, tokens: List[String]) -> String:
    let name = tokens[0]
    let count = tokens.length()

    if name == "stock":
        if count != 3:
            return "error: usage"

        return stock_cmd(var shop, tokens[1], tokens[2])

    if name == "price":
        if count != 3:
            return "error: usage"

        return price_cmd(var shop, tokens[1], tokens[2])

    if name == "order":
        if count < 3:
            return "error: usage"

        return order_cmd(var shop, tokens)

    if name == "cancel":
        if count != 2:
            return "error: usage"

        return cancel_cmd(var shop, tokens[1])

    if name == "ship":
        if count != 2:
            return "error: usage"

        return ship_cmd(var shop, tokens[1])

    if name == "report":
        if count != 1:
            return "error: usage"

        return report(shop)

    return "error: unknown command"

export def main() -> Int:
    var shop = Shop(skus: Map[String, Sku](), orders: Map[String, Order]())
    var out = stdout()

    for line in read_lines(stdin()).get():
        if not is_blank(line):
            let reply = handle(var shop, line.split(" "))
            out.write(f"{reply}\n").get()

    return 0
