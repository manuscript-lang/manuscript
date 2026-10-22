import {read_line, stdin, stdout} from "@std/io.ms"

type Line:
    sku: String
    qty: Int

type Store:
    stock: Map[String, Int]
    prices: Map[String, Int]
    statuses: Map[String, String]
    totals: Map[String, Int]
    lines: Map[String, List[Line]]

fn emit(text: String) Unit:
    stdout().write("{text}\n").get()

fn is_digit(code: Int) Bool:
    return code >= 48 and code <= 57

fn is_sku_char(code: Int) Bool:
    return (code >= 65 and code <= 90) or is_digit(code) or code == 45

fn is_id_char(code: Int) Bool:
    return (code >= 97 and code <= 122) or is_digit(code) or code == 45

fn all_chars(text: String, allowed: fn(code: Int) Bool) Bool:
    if text.length() == 0:
        return false

    for c in text.chars():
        if not allowed(c.scalar_at(0)):
            return false
    return true

fn valid_sku(text: String) Bool:
    return all_chars(text, is_sku_char)

fn valid_id(text: String) Bool:
    return all_chars(text, is_id_char)

fn parse_bounded(text: String, low: Int, high: Int, max_digits: Int) Optional[Int]:
    if text.length() == 0 or text.length() > max_digits:
        return none

    var value = 0

    for c in text.chars():
        let code = c.scalar_at(0)
        if not is_digit(code):
            return none

        value = value * 10 + code - 48

    if value < low or value > high:
        return none

    return some(value)

fn money(cents: Int) String:
    let rest = cents % 100
    if rest < 10:
        return "{cents / 100}.0{rest}"

    return "{cents / 100}.{rest}"

fn compare_text(left: String, right: String) Int:
    return left.compare(right)

fn stock_cmd(var store: Store, sku: String, qty_text: String) Unit:
    if not valid_sku(sku):
        emit("error: bad sku")
        return

    if let qty = parse_bounded(qty_text, 1, 100000, 7):
        if not store.stock.contains(sku):
            store.stock.add(key: sku, value: 0)
            store.prices.add(key: sku, value: 0)

        let now = store.stock.get_or(sku, 0) + qty
        store.stock.add(key: sku, value: now)
        emit("ok {sku} stock={now}")
    else:
        emit("error: bad quantity")

fn price_cmd(var store: Store, sku: String, cents_text: String) Unit:
    if let cents = parse_bounded(cents_text, 0, 10000000, 8):
        if store.stock.contains(sku):
            store.prices.add(key: sku, value: cents)
            emit("ok")
        else:
            emit("error: unknown sku {sku}")
    else:
        emit("error: bad price")

fn order_cmd(var store: Store, id: String, items: List[String]) Unit:
    if not valid_id(id):
        emit("error: bad order id")
        return

    if store.statuses.contains(id):
        emit("error: order {id} already exists")
        return

    var lines = List[Line]()

    for token in items:
        let parts = token.split(":")

        if parts.length() != 2 or not valid_sku(parts.get(0)):
            emit("error: bad item {token}")
            return

        if let qty = parse_bounded(parts.get(1), 1, 100000, 7):
            lines.append(Line(sku: parts.get(0), qty: qty))
        else:
            emit("error: bad item {token}")
            return

    var seen = Map[String, Bool]()

    for line in lines:
        if seen.contains(line.sku):
            emit("error: duplicate sku {line.sku}")
            return

        seen.add(key: line.sku, value: true)

        if not store.stock.contains(line.sku):
            emit("error: unknown sku {line.sku}")
            return

        let have = store.stock.get_or(line.sku, 0)

        if line.qty > have:
            emit(
                "error: insufficient stock for {line.sku} (have {have}, need {line.qty})"
            )
            return

    var total = 0

    for line in lines:
        let price = store.prices.get_or(line.sku, 0)

        if line.qty >= 10:
            total += (line.qty * price * 90 + 50) / 100
        else:
            total += line.qty * price

        (
            store.stock.add(
                key: line.sku, value: store.stock.get_or(line.sku, 0) - line.qty
            )
        )

    store.statuses.add(key: id, value: "placed")
    store.totals.add(key: id, value: total)
    store.lines.add(key: id, value: lines)
    emit("ok {id} total={money(total)}")

fn cancel_cmd(var store: Store, id: String) Unit:
    if not store.statuses.contains(id):
        emit("error: unknown order {id}")
        return

    let status = store.statuses.get_or(id, "")

    if status == "shipped":
        emit("error: order {id} already shipped")
    else if status == "cancelled":
        emit("error: order {id} already cancelled")
    else:
        for line in store.lines.get_or(id, List[Line]()):
            (
                store
                .stock
                .add(
                    key: line.sku,
                    value: store.stock.get_or(
                        line.sku, 0
                    ) + line.qty
                )
            )
        store.statuses.add(key: id, value: "cancelled")
        emit("ok")

fn ship_cmd(var store: Store, id: String) Unit:
    if not store.statuses.contains(id):
        emit("error: unknown order {id}")
        return

    let status = store.statuses.get_or(id, "")

    if status == "shipped":
        emit("error: order {id} already shipped")
    else if status == "cancelled":
        emit("error: order {id} is cancelled")
    else:
        store.statuses.add(key: id, value: "shipped")
        emit("ok")

fn reserved(store: Store, sku: String) Int:
    var units = 0
    for entry in store.statuses.entries():
        if entry.value == "placed":
            for line in store.lines.get_or(entry.key, List[Line]()):
                if line.sku == sku:
                    units += line.qty
    return units

fn report_cmd(store: Store) Unit:
    for sku in store.stock.keys().sorted(compare_text):
        let stock = store.stock.get_or(sku, 0)
        let price = store.prices.get_or(sku, 0)
        emit("{sku} stock={stock} price={money(price)} reserved={reserved(store, sku)}")

    var placed = 0
    var shipped = 0
    var cancelled = 0
    var revenue = 0

    for entry in store.statuses.entries():
        if entry.value == "placed":
            placed += 1
        else if entry.value == "shipped":
            shipped += 1
            revenue += store.totals.get_or(entry.key, 0)
        else:
            cancelled += 1

    emit("orders placed={placed} shipped={shipped} cancelled={cancelled}")
    emit("revenue={money(revenue)}")

fn is_blank(line: String) Bool:
    for c in line.chars():
        if c != " ":
            return false
    return true

fn handle(var store: Store, line: String) Unit:
    let tokens = line.split(" ")
    let count = tokens.length()
    let cmd = tokens.get(0)

    if cmd == "stock":
        if count != 3:
            emit("error: usage")
        else:
            stock_cmd(var store, tokens.get(1), tokens.get(2))
    else if cmd == "price":
        if count != 3:
            emit("error: usage")
        else:
            price_cmd(var store, tokens.get(1), tokens.get(2))
    else if cmd == "order":
        if count < 3:
            emit("error: usage")
        else:
            order_cmd(var store, tokens.get(1), tokens.slice(2, count).get())
    else if cmd == "cancel":
        if count != 2:
            emit("error: usage")
        else:
            cancel_cmd(var store, tokens.get(1))
    else if cmd == "ship":
        if count != 2:
            emit("error: usage")
        else:
            ship_cmd(var store, tokens.get(1))
    else if cmd == "report":
        if count != 1:
            emit("error: usage")
        else:
            report_cmd(store)
    else:
        emit("error: unknown command")

export fn main() Int:
    var store = Store(
        stock: Map[String, Int](), prices: Map[String, Int](),
        statuses: Map[String, String](), totals: Map[String, Int](),
        lines: Map[String, List[Line]]()
    )
    let input = stdin()

    while true:
        if let text = read_line(input).get():
            if not is_blank(text):
                handle(var store, text)
        else:
            break

    stdout().flush().get()
    return 0
