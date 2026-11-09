import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Line:
    sku: String
    qty: Int

type State:
    stock: Map[String, Int]
    price: Map[String, Int]
    skus: List[String]
    status: Map[String, String]
    total: Map[String, Int]
    items: Map[String, List[Line]]

// Value of a 1-to-7-digit ASCII decimal number, or -1 when malformed.
fn num(s: String) Int:
    if s.length() < 1 or s.length() > 7: return -1

    var v = 0

    for c in s.scalar_values():
        if c < 48 or c > 57: return -1

        v = v * 10 + (c - 48)

    return v

fn valid_sku(s: String) Bool:
    if s.length() == 0: return false

    for c in s.scalar_values():
        if not ((c >= 65 and c <= 90) or (c >= 48 and c <= 57) or c == 45): return false
    return true

fn valid_id(s: String) Bool:
    if s.length() == 0: return false

    for c in s.scalar_values():
        if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 45): return false
    return true

fn money(c: Int) String:
    let whole = c / 100
    let frac = "{c % 100}".pad_start(2, "0")
    return "{whole}.{frac}"

fn process(var st: State, line: String) Unit:
    var only_spaces = true
    for c in line.scalar_values():
        if c != 32: only_spaces = false
    if only_spaces: return

    let toks = line.split(" ")
    let n = toks.length()
    let cmd = toks[0]

    if cmd == "stock":
        if n != 3:
            print("error: usage")
            return

        let sku = toks[1]

        if not valid_sku(sku):
            print("error: bad sku")
            return

        let q = num(toks[2])

        if q < 1 or q > 100000:
            print("error: bad quantity")
            return

        if not st.stock.contains(sku):
            st.skus.append(sku.clone())
            st.price[sku.clone()] = 0
            st.stock[sku.clone()] = 0

        let now = st.stock.get_or(sku, 0) + q
        st.stock[sku.clone()] = now
        print("ok {sku} stock={now}")
        return

    if cmd == "price":
        if n != 3:
            print("error: usage")
            return

        let sku = toks[1]
        let p = num(toks[2])

        if p < 0 or p > 10000000:
            print("error: bad price")
            return

        if not st.stock.contains(sku):
            print("error: unknown sku {sku}")
            return

        st.price[sku.clone()] = p
        print("ok")
        return

    if cmd == "order":
        if n < 3:
            print("error: usage")
            return

        let id = toks[1]

        if not valid_id(id):
            print("error: bad order id")
            return

        for i in 2..n:
            let t = toks[i]
            let kv = t.split(":")

            if (
                kv.length() != 2
                or not valid_sku(kv[0])
                or num(kv[1]) < 1
                or num(kv[1]) > 100000
            ):
                print("error: bad item {t}")
                return

        if st.status.contains(id):
            print("error: order {id} already exists")
            return

        var parts = List[Line]()
        var seen = List[String]()
        var total = 0

        for i in 2..n:
            let kv = toks[i].split(":")
            let sku = kv[0]
            let qty = num(kv[1])

            if seen.contains(sku):
                print("error: duplicate sku {sku}")
                return

            if not st.stock.contains(sku):
                print("error: unknown sku {sku}")
                return

            let have = st.stock.get_or(sku, 0)

            if qty > have:
                print("error: insufficient stock for {sku} (have {have}, need {qty})")
                return

            seen.append(sku.clone())

            let raw = qty * st.price.get_or(sku, 0)
            var cost = raw
            if qty >= 10: cost = (raw * 90 + 50) / 100
            total += cost
            parts.append(Line(sku: sku.clone(), qty: qty))

        for p in parts:
            st.stock[p.sku.clone()] = st.stock.get_or(p.sku, 0) - p.qty
        st.status[id.clone()] = "placed"
        st.total[id.clone()] = total
        st.items[id.clone()] = parts
        print("ok {id} total={money(total)}")
        return

    if cmd == "cancel":
        if n != 2:
            print("error: usage")
            return

        let id = toks[1]

        if not st.status.contains(id):
            print("error: unknown order {id}")
            return

        let s = st.status.get_or(id, "")

        if s == "shipped":
            print("error: order {id} already shipped")
            return

        if s == "cancelled":
            print("error: order {id} already cancelled")
            return

        if let ps = st.items.get(id):
            for p in ps:
                st.stock[p.sku.clone()] = st.stock.get_or(p.sku, 0) + p.qty
        st.status[id.clone()] = "cancelled"
        print("ok")
        return

    if cmd == "ship":
        if n != 2:
            print("error: usage")
            return

        let id = toks[1]

        if not st.status.contains(id):
            print("error: unknown order {id}")
            return

        let s = st.status.get_or(id, "")

        if s == "shipped":
            print("error: order {id} already shipped")
            return

        if s == "cancelled":
            print("error: order {id} is cancelled")
            return

        st.status[id.clone()] = "shipped"
        print("ok")
        return

    if cmd == "report":
        if n != 1:
            print("error: usage")
            return

        var placed = 0
        var shipped = 0
        var cancelled = 0
        var revenue = 0
        var reserved = Map[String, Int]()

        for e in st.status.entries():
            if e.value == "placed":
                placed += 1
                if let ps = st.items.get(e.key):
                    for p in ps:
                        reserved[p.sku.clone()] = reserved.get_or(p.sku, 0) + p.qty
            else if e.value == "shipped":
                shipped += 1
                revenue += st.total.get_or(e.key, 0)
            else:
                cancelled += 1

        for sku in st.skus.sorted():
            let s = st.stock.get_or(sku, 0)
            let p = st.price.get_or(sku, 0)
            let r = reserved.get_or(sku, 0)
            print("{sku} stock={s} price={money(p)} reserved={r}")

        print("orders placed={placed} shipped={shipped} cancelled={cancelled}")
        print("revenue={money(revenue)}")
        return

    print("error: unknown command")

fn run() Unit!:
    var st = State(
        stock: Map[String, Int](), price: Map[String, Int](), skus: List[String](),
        status: Map[String, String](), total: Map[String, Int](),
        items: Map[String, List[Line]]()
    )
    for raw in lines(stdin()):
        process(var st, raw)
    return ok(unit)

export fn main() Int:
    run().get()
    return 0
