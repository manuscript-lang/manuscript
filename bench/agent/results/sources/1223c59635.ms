import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

type State:
	stock: Map[String, Int] = Map[String, Int]()
	price: Map[String, Int] = Map[String, Int]()
	status: Map[String, Int] = Map[String, Int]()
	oskus: Map[String, List[String]] = Map[String, List[String]]()
	oqtys: Map[String, List[Int]] = Map[String, List[Int]]()
	totals: Map[String, Int] = Map[String, Int]()

fn all_in(s: String, set: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not set.contains(c): return false
	return true

fn is_sku(s: String) Bool:
	return all_in(s, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")

fn is_id(s: String) Bool:
	return all_in(s, "abcdefghijklmnopqrstuvwxyz0123456789-")

fn num(s: String) Int:
	if s.length() > 7: return -1
	if not all_in(s, "0123456789"): return -1
	return s.parse_int().get(-1)

fn qty_of(s: String) Int:
	n := num(s)
	if n < 1 or n > 100000: return -1
	return n

fn money(c: Int) String:
	r := c % 100
	rs := if r < 10: "0{r}" else: "{r}"
	return "{c / 100}.{rs}"

fn pr(s: String) Unit:
	print(s)

fn var State.order(parts: List[String]) String:
	id := parts.get(1, "")
	if not is_id(id): return "error: bad order id"
	if self.status.contains(id): return "error: order {id} already exists"
	var skus = List[String]()
	var qtys = List[Int]()
	for i in 2..parts.length():
		tok := parts.get(i, "")
		pp := tok.split(":")
		if pp.length() != 2: return "error: bad item {tok}"
		s := pp.get(0, "")
		q := qty_of(pp.get(1, ""))
		if not is_sku(s) or q < 0: return "error: bad item {tok}"
		skus.append(s.clone())
		qtys.append(q)
	var seen = Set[String]()
	var total = 0
	for i in 0..skus.length():
		s := skus.get(i, "")
		q := qtys.get(i, 0)
		if seen.contains(s): return "error: duplicate sku {s}"
		seen.add(s.clone())
		if not self.stock.contains(s): return "error: unknown sku {s}"
		have := self.stock.get_or(s, 0)
		if q > have: return "error: insufficient stock for {s} (have {have}, need {q})"
		p := self.price.get_or(s, 0)
		if q >= 10:
			total += (q * p * 90 + 50) / 100
		else:
			total += q * p
	for i in 0..skus.length():
		s := skus.get(i, "")
		self.stock[s.clone()] = self.stock.get_or(s, 0) - qtys.get(i, 0)
	self.status[id.clone()] = 0
	self.totals[id.clone()] = total
	self.oskus[id.clone()] = skus
	self.oqtys[id.clone()] = qtys
	return "ok {id} total={money(total)}"

fn var State.cancel(id: String) String:
	st := self.status.get_or(id, -1)
	if st < 0: return "error: unknown order {id}"
	if st == 1: return "error: order {id} already shipped"
	if st == 2: return "error: order {id} already cancelled"
	if skus := self.oskus.get(id):
		if qtys := self.oqtys.get(id):
			for i in 0..skus.length():
				s := skus.get(i, "")
				self.stock[s.clone()] = self.stock.get_or(s, 0) + qtys.get(i, 0)
	self.status[id.clone()] = 2
	return "ok"

fn var State.ship(id: String) String:
	st := self.status.get_or(id, -1)
	if st < 0: return "error: unknown order {id}"
	if st == 1: return "error: order {id} already shipped"
	if st == 2: return "error: order {id} is cancelled"
	self.status[id.clone()] = 1
	return "ok"

fn State.report() Unit:
	var reserved = Map[String, Int]()
	var a = 0
	var b = 0
	var c = 0
	var rev = 0
	for e in self.status.entries():
		id := e.key
		if e.value == 0:
			a += 1
			if skus := self.oskus.get(id):
				if qtys := self.oqtys.get(id):
					for i in 0..skus.length():
						s := skus.get(i, "")
						reserved[s.clone()] = reserved.get_or(s, 0) + qtys.get(i, 0)
		else if e.value == 1:
			b += 1
			rev += self.totals.get_or(id, 0)
		else:
			c += 1
	for s in self.stock.keys().sorted():
		pr("{s} stock={self.stock.get_or(s, 0)} price={money(self.price.get_or(s, 0))} reserved={reserved.get_or(s, 0)}")
	pr("orders placed={a} shipped={b} cancelled={c}")
	pr("revenue={money(rev)}")

fn var State.handle(line: String) Unit:
	parts := line.split(" ")
	name := parts.get(0, "")
	n := parts.length()
	if name == "stock":
		if n != 3: return pr("error: usage")
		s := parts.get(1, "")
		if not is_sku(s): return pr("error: bad sku")
		q := qty_of(parts.get(2, ""))
		if q < 0: return pr("error: bad quantity")
		ns := self.stock.get_or(s, 0) + q
		if not self.price.contains(s): self.price[s.clone()] = 0
		self.stock[s.clone()] = ns
		pr("ok {s} stock={ns}")
	else if name == "price":
		if n != 3: return pr("error: usage")
		s := parts.get(1, "")
		p := num(parts.get(2, ""))
		if p < 0 or p > 10000000: return pr("error: bad price")
		if not self.stock.contains(s): return pr("error: unknown sku {s}")
		self.price[s.clone()] = p
		pr("ok")
	else if name == "order":
		if n < 3: return pr("error: usage")
		pr(self.order(parts))
	else if name == "cancel":
		if n != 2: return pr("error: usage")
		pr(self.cancel(parts.get(1, "")))
	else if name == "ship":
		if n != 2: return pr("error: usage")
		pr(self.ship(parts.get(1, "")))
	else if name == "report":
		if n != 1: return pr("error: usage")
		self.report()
	else:
		pr("error: unknown command")

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().ok_or(Error("bad input"))?
	var st = State()
	for raw in text.split("\n"):
		line := raw.trim_end_chars("\r")
		if line.trim_chars(" ").length() == 0: continue
		st.handle(line)
