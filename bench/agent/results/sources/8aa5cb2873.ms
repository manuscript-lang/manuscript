import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

let SKU_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
let ID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789-"
let DIGITS = "0123456789"

fn valid_sku(s: String) Bool:
    if s.length() < 1: return false
    for c in s.chars():
        if not SKU_CHARS.contains(c): return false
    return true

fn valid_id(s: String) Bool:
    if s.length() < 1: return false
    for c in s.chars():
        if not ID_CHARS.contains(c): return false
    return true

# Returns the value of a 1-7 digit ASCII number, or -1 when the syntax is wrong.
fn parse_num(s: String) Int:
    if s.length() < 1 or s.length() > 7: return -1
    for c in s.chars():
        if not DIGITS.contains(c): return -1
    return s.parse_int().get(-1)

fn pad2(n: Int) String:
    if n < 10: return "0{n}"
    return "{n}"

fn money(c: Int) String:
    return "{c / 100}.{pad2(c % 100)}"

type Store:
    stk: Map[String, Int]
    prc: Map[String, Int]
    resv: Map[String, Int]
    state: Map[String, Int]   # 0 placed, 1 shipped, 2 cancelled
    tot: Map[String, Int]
    items: Map[String, String] # "sku:qty sku:qty"
    placed_n: Int
    shipped_n: Int
    cancelled_n: Int
    revenue: Int

impl Store:
    var fn run(line: String) String:
        let tokens = line.split(" ")
        let cmd = tokens[0]
        let n = tokens.length()
        if cmd == "order":
            if n < 3: return "error: usage"
            return self.do_order(tokens)
        if cmd == "stock":
            if n != 3: return "error: usage"
            return self.do_stock(tokens[1].clone(), tokens[2].clone())
        if cmd == "price":
            if n != 3: return "error: usage"
            return self.do_price(tokens[1].clone(), tokens[2].clone())
        if cmd == "cancel":
            if n != 2: return "error: usage"
            return self.do_cancel(tokens[1].clone())
        if cmd == "ship":
            if n != 2: return "error: usage"
            return self.do_ship(tokens[1].clone())
        if cmd == "report":
            if n != 1: return "error: usage"
            return self.do_report()
        return "error: unknown command"

    var fn do_stock(sku: String, qty: String) String:
        if not valid_sku(sku): return "error: bad sku"
        let q = parse_num(qty)
        if q < 1 or q > 100000: return "error: bad quantity"
        if not self.stk.contains(sku):
            self.prc[sku.clone()] = 0
        let now = self.stk.get_or(sku, 0) + q
        self.stk[sku.clone()] = now
        return "ok {sku} stock={now}"

    var fn do_price(sku: String, cents: String) String:
        let c = parse_num(cents)
        if c < 0 or c > 10000000: return "error: bad price"
        if not self.stk.contains(sku): return "error: unknown sku {sku}"
        self.prc[sku.clone()] = c
        return "ok"

    var fn do_order(tokens: List[String]) String:
        let id = tokens[1]
        if not valid_id(id): return "error: bad order id"
        # Syntax of every item first.
        for i in 2..tokens.length():
            let parts = tokens[i].split(":")
            if parts.length() != 2 or not valid_sku(parts[0]) or parse_num(parts[1]) < 1 or parse_num(parts[1]) > 100000:
                return "error: bad item {tokens[i]}"
        if self.state.contains(id): return "error: order {id} already exists"
        # Semantic checks, item by item in the order given.
        var seen = List[String]()
        for i in 2..tokens.length():
            let parts = tokens[i].split(":")
            let sku = parts[0]
            let q = parse_num(parts[1])
            if seen.contains(sku): return "error: duplicate sku {sku}"
            if not self.stk.contains(sku): return "error: unknown sku {sku}"
            let have = self.stk.get_or(sku, 0)
            if q > have: return "error: insufficient stock for {sku} (have {have}, need {q})"
            seen.append(sku.clone())
        # All fine: apply.
        var total = 0
        var spec = List[String]()
        for i in 2..tokens.length():
            let parts = tokens[i].split(":")
            let sku = parts[0]
            let q = parse_num(parts[1])
            let p = self.prc.get_or(sku, 0)
            let raw = q * p
            if q >= 10:
                total += (raw * 90 + 50) / 100
            else:
                total += raw
            self.stk[sku.clone()] = self.stk.get_or(sku, 0) - q
            self.resv[sku.clone()] = self.resv.get_or(sku, 0) + q
            spec.append("{sku}:{q}")
        self.state[id.clone()] = 0
        self.tot[id.clone()] = total
        self.items[id.clone()] = spec.join(" ")
        self.placed_n += 1
        return "ok {id} total={money(total)}"

    var fn do_cancel(id: String) String:
        if not self.state.contains(id): return "error: unknown order {id}"
        let st = self.state.get_or(id, 0)
        if st == 1: return "error: order {id} already shipped"
        if st == 2: return "error: order {id} already cancelled"
        for t in self.items.get_or(id, "").split(" "):
            let parts = t.split(":")
            let sku = parts[0]
            let q = parse_num(parts[1])
            self.stk[sku.clone()] = self.stk.get_or(sku, 0) + q
            self.resv[sku.clone()] = self.resv.get_or(sku, 0) - q
        self.state[id.clone()] = 2
        self.placed_n -= 1
        self.cancelled_n += 1
        return "ok"

    var fn do_ship(id: String) String:
        if not self.state.contains(id): return "error: unknown order {id}"
        let st = self.state.get_or(id, 0)
        if st == 1: return "error: order {id} already shipped"
        if st == 2: return "error: order {id} is cancelled"
        for t in self.items.get_or(id, "").split(" "):
            let parts = t.split(":")
            let sku = parts[0]
            let q = parse_num(parts[1])
            self.resv[sku.clone()] = self.resv.get_or(sku, 0) - q
        self.state[id.clone()] = 1
        self.placed_n -= 1
        self.shipped_n += 1
        self.revenue += self.tot.get_or(id, 0)
        return "ok"

    var fn do_report() String:
        var out = List[String]()
        for sku in self.stk.keys().sorted():
            let s = self.stk.get_or(sku, 0)
            let p = self.prc.get_or(sku, 0)
            let r = self.resv.get_or(sku, 0)
            out.append("{sku} stock={s} price={money(p)} reserved={r}")
        out.append("orders placed={self.placed_n} shipped={self.shipped_n} cancelled={self.cancelled_n}")
        out.append("revenue={money(self.revenue)}")
        return out.join("\n")

fn is_blank(line: String) Bool:
    return line.split(" ").join("").is_empty()

export fn main() Int:
    var st = Store(stk: Map[String, Int](), prc: Map[String, Int](), resv: Map[String, Int](), state: Map[String, Int](), tot: Map[String, Int](), items: Map[String, String](), placed_n: 0, shipped_n: 0, cancelled_n: 0, revenue: 0)
    var out = List[String]()
    for line in read_lines(stdin()).get():
        if is_blank(line): continue
        out.append(st.run(line))
    if out.length() > 0:
        stdout().write(out.join("\n") + "\n").get()
    return 0
