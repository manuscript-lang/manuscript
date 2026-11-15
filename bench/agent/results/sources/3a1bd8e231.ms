import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

SKU_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
ID_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789-"
DIGITS := "0123456789"

fn all_in(s: String, set: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not set.contains(c): return false
	return true

fn num(s: String) Int:
	if s.length() < 1 or s.length() > 7: return -1
	if not all_in(s, DIGITS): return -1
	return s.parse_int().get(-1)

fn qty_of(s: String) Int:
	n := num(s)
	if n < 1 or n > 100000: return -1
	return n

fn money(c: Int) String:
	r := c % 100
	rs := if r < 10: "0{r}" else: "{r}"
	return "{c / 100}.{rs}"

type Order:
	skus: List[String]
	qtys: List[Int]
	total: Int
	status: Int

type State:
	stock: Map[String, Int]
	price: Map[String, Int]
	orders: Map[String, Order]

fn var State.exec(line: String) String:
	t := line.split(" ")
	n := t.length()
	cmd := t.get(0, "")
	if cmd == "stock":
		if n != 3: return "error: usage"
		sku := t.get(1, "")
		if not all_in(sku, SKU_CHARS): return "error: bad sku"
		q := qty_of(t.get(2, ""))
		if q < 0: return "error: bad quantity"
		ns := self.stock.get_or(sku, 0) + q
		if not self.price.contains(sku): self.price[sku.clone()] = 0
		self.stock[sku.clone()] = ns
		return "ok {sku} stock={ns}"
	if cmd == "price":
		if n != 3: return "error: usage"
		sku := t.get(1, "")
		p := num(t.get(2, ""))
		if p < 0 or p > 10000000: return "error: bad price"
		if not self.stock.contains(sku): return "error: unknown sku {sku}"
		self.price[sku.clone()] = p
		return "ok"
	if cmd == "order":
		if n < 3: return "error: usage"
		id := t.get(1, "")
		if not all_in(id, ID_CHARS): return "error: bad order id"
		if self.orders.contains(id): return "error: order {id} already exists"
		var skus = List[String]()
		var qtys = List[Int]()
		for i in 2..n:
			tok := t.get(i, "")
			parts := tok.split(":")
			if parts.length() != 2: return "error: bad item {tok}"
			s := parts.get(0, "")
			q := qty_of(parts.get(1, ""))
			if not all_in(s, SKU_CHARS) or q < 0: return "error: bad item {tok}"
			skus.append(s.clone())
			qtys.append(q)
		var seen = Set[String]()
		for i in 0..skus.length():
			s := skus.get(i, "")
			q := qtys.get(i, 0)
			if seen.contains(s): return "error: duplicate sku {s}"
			seen.add(s.clone())
			if not self.stock.contains(s): return "error: unknown sku {s}"
			have := self.stock.get_or(s, 0)
			if q > have: return "error: insufficient stock for {s} (have {have}, need {q})"
		var total = 0
		for i in 0..skus.length():
			s := skus.get(i, "")
			q := qtys.get(i, 0)
			p := self.price.get_or(s, 0)
			if q >= 10:
				total += (q * p * 90 + 50) / 100
			else:
				total += q * p
			self.stock[s.clone()] = self.stock.get_or(s, 0) - q
		self.orders[id.clone()] = Order(skus, qtys, total, 0)
		return "ok {id} total={money(total)}"
	if cmd == "cancel" or cmd == "ship":
		if n != 2: return "error: usage"
		id := t.get(1, "")
		if not self.orders.contains(id): return "error: unknown order {id}"
		o := self.orders.get_or(id, Order(List[String](), List[Int](), 0, 0))
		if o.status == 1: return "error: order {id} already shipped"
		if o.status == 2:
			if cmd == "cancel": return "error: order {id} already cancelled"
			return "error: order {id} is cancelled"
		if cmd == "ship":
			self.orders[id.clone()] = Order(o.skus.clone(), o.qtys.clone(), o.total, 1)
			return "ok"
		for i in 0..o.skus.length():
			s := o.skus.get(i, "")
			self.stock[s.clone()] = self.stock.get_or(s, 0) + o.qtys.get(i, 0)
		self.orders[id.clone()] = Order(o.skus.clone(), o.qtys.clone(), o.total, 2)
		return "ok"
	if cmd == "report":
		if n != 1: return "error: usage"
		var keys = List[String]()
		for e in self.stock.entries():
			keys.append(e.key.clone())
		keys.sort()
		var reserved = Map[String, Int]()
		var a = 0
		var b = 0
		var c = 0
		var rev = 0
		for e in self.orders.entries():
			o := e.value
			if o.status == 0:
				a += 1
				for i in 0..o.skus.length():
					s := o.skus.get(i, "")
					reserved[s.clone()] = reserved.get_or(s, 0) + o.qtys.get(i, 0)
			else if o.status == 1:
				b += 1
				rev += o.total
			else:
				c += 1
		var out = ""
		for k in keys:
			out += "{k} stock={self.stock.get_or(k, 0)} price={money(self.price.get_or(k, 0))} reserved={reserved.get_or(k, 0)}\n"
		out += "orders placed={a} shipped={b} cancelled={c}\n"
		out += "revenue={money(rev)}"
		return out
	return "error: unknown command"

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	var st = State(Map[String, Int](), Map[String, Int](), Map[String, Order]())
	for line in lines(stdin()):
		if line.trim_chars(" ").length() == 0: continue
		print(st.exec(line))
