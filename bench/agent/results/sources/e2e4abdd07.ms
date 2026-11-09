import read_all from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"

type Item:
    sku: String
    qty: Int

type Shop:
    stock: Map[String, Int]
    price: Map[String, Int]
    reserved: Map[String, Int]
    status: Map[String, Int]  // 0 placed, 1 shipped, 2 cancelled
    total: Map[String, Int]
    items: Map[String, List[Item]]
    skus: List[String]
    placed: Int
    shipped: Int
    cancelled: Int
    revenue: Int

fn is_sku_byte(c: Int) Bool:
    return (c >= 65 and c <= 90) or (c >= 48 and c <= 57) or c == 45

fn is_id_byte(c: Int) Bool:
    return (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 45

fn valid_sku(s: String) Bool:
    let b = s.as_bytes()
    if b.length() == 0: return false

    for i in 0..b.length():
        if not is_sku_byte(b[i].to_int()): return false
    return true

fn valid_id(s: String) Bool:
    let b = s.as_bytes()
    if b.length() == 0: return false

    for i in 0..b.length():
        if not is_id_byte(b[i].to_int()): return false
    return true

// Returns the value of 1 to 7 ASCII digits, or -1 when malformed.
fn parse_num(s: String) Int:
    let b = s.as_bytes()
    if b.length() == 0 or b.length() > 7: return -1

    var v = 0

    for i in 0..b.length():
        let c = b[i].to_int()
        if c < 48 or c > 57: return -1

        v = v * 10 + (c - 48)

    return v

fn money(c: Int) String:
    let d = c / 100
    let r = c % 100
    if r < 10: return "{d}.0{r}"

    return "{d}.{r}"

// Line total in cents; qty >= 10 gets 10% off, rounded half up.
fn line_cost(qty: Int, price: Int) Int:
    let raw = qty * price
    if qty >= 10: return (raw * 90 + 50) / 100

    return raw

impl Shop:
    var fn do_stock(sku: String, qty_text: String) String:
        if not valid_sku(sku): return "error: bad sku"

        let q = parse_num(qty_text)
        if q < 1 or q > 100000: return "error: bad quantity"

        if not self.price.contains(sku):
            self.price[sku.clone()] = 0
            self.reserved[sku.clone()] = 0
            self.skus.append(sku.clone())

        let now = self.stock.get_or(sku, 0) + q
        self.stock[sku.clone()] = now
        return "ok {sku} stock={now}"

    var fn do_price(sku: String, cents_text: String) String:
        let c = parse_num(cents_text)
        if c < 0 or c > 10000000: return "error: bad price"
        if not self.price.contains(sku): return "error: unknown sku {sku}"

        self.price[sku.clone()] = c
        return "ok"

    var fn do_order(t: List[String]) String:
        let id = t[1].clone()
        if not valid_id(id): return "error: bad order id"

        var its = List[Item]()

        for i in 2..t.length():
            let tok = t[i].clone()
            let parts = tok.split(":")
            if parts.length() != 2 or not valid_sku(parts[0]): return "error: bad item {tok}"

            let q = parse_num(parts[1])
            if q < 1 or q > 100000: return "error: bad item {tok}"

            its.append(Item(sku: parts[0].clone(), qty: q))

        if self.status.contains(id): return "error: order {id} already exists"

        for i in 0..its.length():
            let sku = its[i].sku.clone()
            for j in 0..i:
                if its[j].sku == sku: return "error: duplicate sku {sku}"
            if not self.price.contains(sku): return "error: unknown sku {sku}"

            let have = self.stock.get_or(sku, 0)
            let need = its[i].qty
            if need > have: return "error: insufficient stock for {sku} (have {have}, need {need})"

        var total = 0

        for i in 0..its.length():
            let sku = its[i].sku.clone()
            let qty = its[i].qty
            let p = self.price.get_or(sku, 0)
            total += line_cost(qty, p)
            self.stock[sku.clone()] = self.stock.get_or(sku, 0) - qty
            self.reserved[sku.clone()] = self.reserved.get_or(sku, 0) + qty

        self.status[id.clone()] = 0
        self.total[id.clone()] = total
        self.items[id.clone()] = its
        self.placed += 1
        return "ok {id} total={money(total)}"

    var fn do_cancel(id: String) String:
        if not self.status.contains(id): return "error: unknown order {id}"

        let st = self.status.get_or(id, 0)
        if st == 1: return "error: order {id} already shipped"
        if st == 2: return "error: order {id} already cancelled"

        let its = self.items.get_or(id, List[Item]())

        for i in 0..its.length():
            let sku = its[i].sku.clone()
            let qty = its[i].qty
            self.stock[sku.clone()] = self.stock.get_or(sku, 0) + qty
            self.reserved[sku.clone()] = self.reserved.get_or(sku, 0) - qty

        self.status[id.clone()] = 2
        self.placed -= 1
        self.cancelled += 1
        return "ok"

    var fn do_ship(id: String) String:
        if not self.status.contains(id): return "error: unknown order {id}"

        let st = self.status.get_or(id, 0)
        if st == 1: return "error: order {id} already shipped"
        if st == 2: return "error: order {id} is cancelled"

        let its = self.items.get_or(id, List[Item]())

        for i in 0..its.length():
            let sku = its[i].sku.clone()
            let qty = its[i].qty
            self.reserved[sku.clone()] = self.reserved.get_or(sku, 0) - qty

        self.status[id.clone()] = 1
        self.placed -= 1
        self.shipped += 1
        self.revenue += self.total.get_or(id, 0)
        return "ok"

    var fn do_report() String:
        var lines = List[String]()

        for sku in self.skus.sorted():
            let st = self.stock.get_or(sku, 0)
            let p = self.price.get_or(sku, 0)
            let r = self.reserved.get_or(sku, 0)
            lines.append("{sku} stock={st} price={money(p)} reserved={r}")

        lines.append(
            "orders placed={self.placed} shipped={self.shipped} cancelled={self.cancelled}"
        )
        lines.append("revenue={money(self.revenue)}")
        return lines.join("\n")

    var fn run(t: List[String]) String:
        let cmd = t[0].clone()
        let n = t.length()
        if (
            cmd != "stock"
            and cmd != "price"
            and cmd != "order"
            and cmd != "cancel"
            and cmd != "ship"
            and cmd != "report"
        ):
            return "error: unknown command"

        if cmd == "stock":
            if n != 3: return "error: usage"

            return self.do_stock(t[1].clone(), t[2].clone())

        if cmd == "price":
            if n != 3: return "error: usage"

            return self.do_price(t[1].clone(), t[2].clone())

        if cmd == "order":
            if n < 3: return "error: usage"

            return self.do_order(t)

        if cmd == "cancel":
            if n != 2: return "error: usage"

            return self.do_cancel(t[1].clone())

        if cmd == "ship":
            if n != 2: return "error: usage"

            return self.do_ship(t[1].clone())

        if n != 1: return "error: usage"

        return self.do_report()

export fn main() Int:
    let text = read_all(stdin()).get().decode_utf8().get("")
    var shop = Shop(
        stock: Map[String, Int](), price: Map[String, Int](),
        reserved: Map[String, Int](), status: Map[String, Int](),
        total: Map[String, Int](), items: Map[String, List[Item]](),
        skus: List[String](), placed: 0, shipped: 0, cancelled: 0, revenue: 0
    )

    for raw in text.split("\n"):
        let t = raw.split(" ")
        var blank = true
        for tok in t:
            if tok.length() > 0: blank = false
        if blank: continue

        print(shop.run(t))

    return 0
