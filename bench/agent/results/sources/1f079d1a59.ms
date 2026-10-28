import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Item:
    sku: String
    qty: Int

type Order:
    status: String
    items: List[Item]
    total: Int

type Shop:
    stock: Map[String, Int]
    price: Map[String, Int]
    orders: Map[String, Order]

fn is_digit(c: String) Bool:
    return "0" <= c and c <= "9"

fn valid_sku(text: String) Bool:
    if text.length() == 0:
        return false

    for i in 0..text.length():
        let c = text.get(i)
        if not (("A" <= c and c <= "Z") or is_digit(c) or c == "-"):
            return false

    return true

fn valid_id(text: String) Bool:
    if text.length() == 0:
        return false

    for i in 0..text.length():
        let c = text.get(i)
        if not (("a" <= c and c <= "z") or is_digit(c) or c == "-"):
            return false

    return true

fn parse_num(text: String, lo: Int, hi: Int) Optional[Int]:
    if text.length() < 1 or text.length() > 7:
        return none

    for i in 0..text.length():
        if not is_digit(text.get(i)):
            return none

    let value = text.parse_int().get(0)
    if value < lo or value > hi:
        return none

    return some(value)

fn money(cents: Int) String:
    let frac = cents % 100
    if frac < 10:
        return "{cents / 100}.0{frac}"

    return "{cents / 100}.{frac}"

fn line_cost(qty: Int, price: Int) Int:
    if qty >= 10:
        return (qty * price * 90 + 50) / 100

    return qty * price

impl Shop:
    var fn stock_cmd(parts: List[String]) String:
        if parts.length() != 3:
            return "error: usage"
        if not valid_sku(parts[1]):
            return "error: bad sku"

        if let qty = parse_num(parts[2], 1, 100000):
            let sku = parts[1]
            if not self.price.contains(sku):
                self.price[sku.clone()] = 0

            let now = self.stock.get(sku).get(0) + qty
            self.stock[sku.clone()] = now
            return "ok {sku} stock={now}"

        return "error: bad quantity"

    var fn price_cmd(parts: List[String]) String:
        if parts.length() != 3:
            return "error: usage"

        if let cents = parse_num(parts[2], 0, 10000000):
            let sku = parts[1]
            if not self.price.contains(sku):
                return "error: unknown sku {sku}"

            self.price[sku.clone()] = cents
            return "ok"

        return "error: bad price"

    var fn order_cmd(parts: List[String]) String:
        if parts.length() < 3:
            return "error: usage"

        let id = parts[1]
        if not valid_id(id):
            return "error: bad order id"

        var items = List[Item]()

        for i in 2..parts.length():
            let pieces = parts[i].split(":")
            if pieces.length() != 2 or not valid_sku(pieces[0]):
                return "error: bad item {parts[i]}"

            if let qty = parse_num(pieces[1], 1, 100000):
                items.append(Item(pieces[0].clone(), qty))
            else:
                return "error: bad item {parts[i]}"

        if self.orders.contains(id):
            return "error: order {id} already exists"

        var seen = Set[String]()

        for it in items:
            if seen.contains(it.sku):
                return "error: duplicate sku {it.sku}"

            seen.add(it.sku.clone())
            if not self.price.contains(it.sku):
                return "error: unknown sku {it.sku}"

            let have = self.stock.get(it.sku).get(0)
            if it.qty > have:
                return "error: insufficient stock for {it.sku} (have {have}, need {it.qty})"

        var total = 0
        for it in items:
            total += line_cost(it.qty, self.price.get(it.sku).get(0))
        for it in items:
            self.stock[it.sku.clone()] = self.stock.get(it.sku).get(0) - it.qty
        self.orders[id.clone()] = Order("placed", items, total)
        return "ok {id} total={money(total)}"

    var fn cancel_cmd(parts: List[String]) String:
        if parts.length() != 2:
            return "error: usage"

        let id = parts[1]

        if let o = self.orders.get(id).clone():
            if o.status == "shipped":
                return "error: order {id} already shipped"
            if o.status == "cancelled":
                return "error: order {id} already cancelled"

            for it in o.items:
                self.stock[it.sku.clone()] = self.stock.get(it.sku).get(0) + it.qty
            self.orders[id.clone()] = Order("cancelled", o.items.clone(), o.total)
            return "ok"

        return "error: unknown order {id}"

    var fn ship_cmd(parts: List[String]) String:
        if parts.length() != 2:
            return "error: usage"

        let id = parts[1]

        if let o = self.orders.get(id).clone():
            if o.status == "shipped":
                return "error: order {id} already shipped"
            if o.status == "cancelled":
                return "error: order {id} is cancelled"

            self.orders[id.clone()] = Order("shipped", o.items.clone(), o.total)
            return "ok"

        return "error: unknown order {id}"

    fn report() String:
        var lines = List[String]()
        var placed = 0
        var shipped = 0
        var cancelled = 0
        var revenue = 0

        for e in self.orders.entries():
            if e.value.status == "placed":
                placed += 1
            else if e.value.status == "shipped":
                shipped += 1
                revenue += e.value.total
            else:
                cancelled += 1

        for sku in self.stock.keys().sorted():
            var reserved = 0
            for e in self.orders.entries():
                if e.value.status == "placed":
                    for it in e.value.items:
                        if it.sku == sku:
                            reserved += it.qty
            lines.append(
                "{sku} stock={self.stock.get(sku).get(0)} price={money(self.price.get(sku).get(0))} reserved={reserved}"
            )

        lines.append("orders placed={placed} shipped={shipped} cancelled={cancelled}")
        lines.append("revenue={money(revenue)}")
        return lines.join("\n")

    var fn handle(parts: List[String]) String:
        let cmd = parts[0]
        if cmd == "stock":
            return self.stock_cmd(parts)
        if cmd == "price":
            return self.price_cmd(parts)
        if cmd == "order":
            return self.order_cmd(parts)
        if cmd == "cancel":
            return self.cancel_cmd(parts)
        if cmd == "ship":
            return self.ship_cmd(parts)

        if cmd == "report":
            if parts.length() != 1:
                return "error: usage"

            return self.report()

        return "error: unknown command"

fn is_blank(parts: List[String]) Bool:
    for p in parts:
        if p != "":
            return false
    return true

export fn main() Int:
    var shop = Shop(Map[String, Int](), Map[String, Int](), Map[String, Order]())

    for line in read_lines(stdin()).get():
        let parts = line.split(" ")
        if is_blank(parts):
            continue

        let out = shop.handle(parts)
        stdout().write("{out}\n").get()

    return 0
