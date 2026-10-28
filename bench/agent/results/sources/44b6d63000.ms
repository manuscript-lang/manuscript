import {read_lines} from "@std/streams.ms"
import {stdin, stdout} from "@std/io.ms"

let SKU_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
let ID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789-"
let DIGITS = "0123456789"

type Sku:
    stock: Int
    price: Int
    reserved: Int

type Line:
    sku: String
    qty: Int

type Order:
    status: String
    total: Int
    lines: List[Line]

type Store:
    skus: Map[String, Sku]
    orders: Map[String, Order]

fn all_in(text: String, allowed: String) Bool:
    for i in 0..text.length():
        if not allowed.contains(text.get(i)):
            return false
    return true

fn valid_sku(text: String) Bool:
    return text.length() > 0 and all_in(text, SKU_CHARS)

fn valid_id(text: String) Bool:
    return text.length() > 0 and all_in(text, ID_CHARS)

# A number is 1 to 7 ASCII digits.
fn number(text: String) Optional[Int]:
    if text.length() == 0 or text.length() > 7 or not all_in(text, DIGITS):
        return none

    return text.parse_int()

fn quantity(text: String) Optional[Int]:
    if let n = number(text):
        if n >= 1 and n <= 100000:
            return some(n)
    return none

fn price_cents(text: String) Optional[Int]:
    if let n = number(text):
        if n <= 10000000:
            return some(n)
    return none

fn money(cents: Int) String:
    let rest = cents % 100
    if rest < 10:
        return "{cents / 100}.0{rest}"

    return "{cents / 100}.{rest}"

fn line_cost(qty: Int, price: Int) Int:
    if qty >= 10:
        return (qty * price * 90 + 50) / 100

    return qty * price

fn parse_item(token: String) Optional[Line]:
    let parts = token.split(":")
    if parts.length() != 2 or not valid_sku(parts[0].clone()):
        return none
    if let qty = quantity(parts[1].clone()):
        return some(Line(sku: parts[0].clone(), qty: qty))

    return none

fn blank(line: String) Bool:
    for i in 0..line.length():
        if line.get(i) != " ":
            return false
    return true

impl Store:
    var fn add_stock(sku: String, qty: Int) String:
        let old = self.skus.get_or(sku.clone(), Sku(stock: 0, price: 0, reserved: 0))
        let updated = Sku(
            stock: old.stock + qty, price: old.price, reserved: old.reserved
        )
        self.skus[sku.clone()] = updated
        return "ok {sku} stock={updated.stock}"

    var fn set_price(sku: String, cents: Int) String:
        let old = self.skus[sku.clone()]
        self.skus[sku] = Sku(stock: old.stock, price: cents, reserved: old.reserved)
        return "ok"

    var fn place(id: String, lines: List[Line]) String:
        for i in 0..lines.length():
            let line = lines[i].clone()
            for j in 0..i:
                if lines[j].sku == line.sku:
                    return "error: duplicate sku {line.sku}"
            if not self.skus.contains(line.sku.clone()):
                return "error: unknown sku {line.sku}"

            let sku = self.skus[line.sku.clone()]
            if line.qty > sku.stock:
                return "error: insufficient stock for {line.sku} (have {sku.stock}, need {line.qty})"

        var total = 0

        for line in lines.clone():
            let sku = self.skus[line.sku.clone()]
            self.skus[line.sku.clone()] = Sku(
                stock: sku.stock - line.qty, price: sku.price,
                reserved: sku.reserved + line.qty
            )
            total += line_cost(line.qty, sku.price)

        self.orders[id.clone()] = Order(status: "placed", total: total, lines: lines)
        return "ok {id} total={money(total)}"

    var fn cancel(id: String) String:
        let order = self.orders[id.clone()].clone()
        if order.status == "cancelled":
            return "error: order {id} already cancelled"
        if order.status == "shipped":
            return "error: order {id} already shipped"

        for line in order.lines:
            let sku = self.skus[line.sku.clone()]
            self.skus[line.sku.clone()] = Sku(
                stock: sku.stock + line.qty, price: sku.price,
                reserved: sku.reserved - line.qty
            )

        self.orders[id.clone()] = Order(
            status: "cancelled", total: order.total, lines: order.lines.clone()
        )
        return "ok"

    var fn ship(id: String) String:
        let order = self.orders[id.clone()].clone()
        if order.status == "shipped":
            return "error: order {id} already shipped"
        if order.status == "cancelled":
            return "error: order {id} is cancelled"

        for line in order.lines:
            let sku = self.skus[line.sku.clone()]
            self.skus[line.sku.clone()] = Sku(
                stock: sku.stock, price: sku.price, reserved: sku.reserved - line.qty
            )

        self.orders[id.clone()] = Order(
            status: "shipped", total: order.total, lines: order.lines.clone()
        )
        return "ok"

    fn report() String:
        var out = List[String]()

        for sku in self.skus.keys().sorted():
            let s = self.skus[sku.clone()]
            out.append(
                "{sku} stock={s.stock} price={money(s.price)} reserved={s.reserved}"
            )

        var placed = 0
        var shipped = 0
        var cancelled = 0
        var revenue = 0

        for id in self.orders.keys():
            let order = self.orders[id.clone()]

            if order.status == "placed":
                placed += 1
            else if order.status == "shipped":
                shipped += 1
                revenue += order.total
            else:
                cancelled += 1

        out.append("orders placed={placed} shipped={shipped} cancelled={cancelled}")
        out.append("revenue={money(revenue)}")
        return out.join("\n")

fn run(var store: Store, tokens: List[String]) String:
    let name = tokens[0].clone()
    let count = tokens.length()

    if name == "stock":
        if count != 3:
            return "error: usage"
        if not valid_sku(tokens[1].clone()):
            return "error: bad sku"
        if let qty = quantity(tokens[2].clone()):
            return store.add_stock(tokens[1].clone(), qty)

        return "error: bad quantity"

    if name == "price":
        if count != 3:
            return "error: usage"

        if let cents = price_cents(tokens[2].clone()):
            if not store.skus.contains(tokens[1].clone()):
                return "error: unknown sku {tokens[1]}"

            return store.set_price(tokens[1].clone(), cents)

        return "error: bad price"

    if name == "order":
        if count < 3:
            return "error: usage"
        if not valid_id(tokens[1].clone()):
            return "error: bad order id"
        if store.orders.contains(tokens[1].clone()):
            return "error: order {tokens[1]} already exists"

        var lines = List[Line]()

        for i in 2..count:
            if let line = parse_item(tokens[i].clone()):
                lines.append(line)
            else:
                return "error: bad item {tokens[i]}"

        return store.place(tokens[1].clone(), lines)

    if name == "cancel":
        if count != 2:
            return "error: usage"
        if not store.orders.contains(tokens[1].clone()):
            return "error: unknown order {tokens[1]}"

        return store.cancel(tokens[1].clone())

    if name == "ship":
        if count != 2:
            return "error: usage"
        if not store.orders.contains(tokens[1].clone()):
            return "error: unknown order {tokens[1]}"

        return store.ship(tokens[1].clone())

    if name == "report":
        if count != 1:
            return "error: usage"

        return store.report()

    return "error: unknown command"

export fn main() Int:
    var store = Store(skus: Map[String, Sku](), orders: Map[String, Order]())
    var out = stdout()

    if let lines = read_lines(stdin()):
        for line in lines:
            if blank(line.clone()):
                continue

            let reply = run(var store, line.split(" "))
            out.write("{reply}\n").get()

    return 0
