import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

fn all_in(s: String, ok_chars: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not ok_chars.contains(c): return false
	return true

fn valid_sku(s: String) Bool:
	return all_in(s, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")

fn valid_id(s: String) Bool:
	return all_in(s, "abcdefghijklmnopqrstuvwxyz0123456789-")

fn number(s: String) Int:
	if s.length() > 7: return -1
	if not all_in(s, "0123456789"): return -1
	return s.parse_int().get(-1)

fn qty_of(s: String) Int:
	n := number(s)
	if n >= 1 and n <= 100000: return n
	return -1

fn price_of(s: String) Int:
	n := number(s)
	if n >= 0 and n <= 10000000: return n
	return -1

fn money(c: Int) String:
	r := c % 100
	return "{c / 100}.{r.to_string().pad_start(2, "0")}"

type State:
	stock: Map[String, Int] = Map[String, Int]()
	prices: Map[String, Int] = Map[String, Int]()
	status: Map[String, Int] = Map[String, Int]()
	skus: Map[String, List[String]] = Map[String, List[String]]()
	qtys: Map[String, List[Int]] = Map[String, List[Int]]()
	totals: Map[String, Int] = Map[String, Int]()

fn var State.order(toks: List[String]) String:
	id := toks.get(1, "")
	if not valid_id(id): return "error: bad order id"
	if self.status.get(id).is_some(): return "error: order {id} already exists"
	var ss = List[String]()
	var qs = List[Int]()
	for i in 2..toks.length():
		t := toks.get(i, "")
		parts := t.split(":")
		if parts.length() != 2: return "error: bad item {t}"
		sk := parts.get(0, "")
		if not valid_sku(sk): return "error: bad item {t}"
		q := qty_of(parts.get(1, ""))
		if q < 0: return "error: bad item {t}"
		ss.append(sk.clone())
		qs.append(q)
	var seen = Set[String]()
	var total = 0
	for i in 0..ss.length():
		sk := ss.get(i, "")
		q := qs.get(i, 0)
		if seen.contains(sk): return "error: duplicate sku {sk}"
		seen.add(sk.clone())
		have := self.stock.get_or(sk, -1)
		if have < 0: return "error: unknown sku {sk}"
		if q > have: return "error: insufficient stock for {sk} (have {have}, need {q})"
		p := self.prices.get_or(sk, 0)
		if q >= 10:
			total += (q * p * 90 + 50) / 100
		else:
			total += q * p
	for i in 0..ss.length():
		sk := ss.get(i, "")
		self.stock[sk.clone()] = self.stock.get_or(sk, 0) - qs.get(i, 0)
	self.status[id.clone()] = 0
	self.totals[id.clone()] = total
	self.skus[id.clone()] = ss
	self.qtys[id.clone()] = qs
	return "ok {id} total={money(total)}"

fn var State.report() String:
	var out = List[String]()
	var reserved = Map[String, Int]()
	var a = 0
	var b = 0
	var c = 0
	var rev = 0
	for e in self.status.entries():
		id := e.key
		if e.value == 0:
			a += 1
			ss := self.skus.get_or(id, [])
			qs := self.qtys.get_or(id, [])
			for i in 0..ss.length():
				k := ss.get(i, "")
				reserved[k.clone()] = reserved.get_or(k, 0) + qs.get(i, 0)
		else if e.value == 1:
			b += 1
			rev += self.totals.get_or(id, 0)
		else:
			c += 1
	ks := self.stock.keys().sorted()
	for k in ks:
		out.append("{k} stock={self.stock.get_or(k, 0)} price={money(self.prices.get_or(k, 0))} reserved={reserved.get_or(k, 0)}")
	out.append("orders placed={a} shipped={b} cancelled={c}")
	out.append("revenue={money(rev)}")
	return out.join("\n")

fn var State.handle(line: String) String:
	toks := line.split(" ")
	cmd := toks.get(0, "")
	n := toks.length()
	if cmd == "stock":
		if n != 3: return "error: usage"
		sk := toks.get(1, "")
		if not valid_sku(sk): return "error: bad sku"
		q := qty_of(toks.get(2, ""))
		if q < 0: return "error: bad quantity"
		ns := self.stock.get_or(sk, 0) + q
		if self.stock.get(sk).is_none(): self.prices[sk.clone()] = 0
		self.stock[sk.clone()] = ns
		return "ok {sk} stock={ns}"
	if cmd == "price":
		if n != 3: return "error: usage"
		sk := toks.get(1, "")
		p := price_of(toks.get(2, ""))
		if p < 0: return "error: bad price"
		if self.stock.get(sk).is_none(): return "error: unknown sku {sk}"
		self.prices[sk.clone()] = p
		return "ok"
	if cmd == "order":
		if n < 3: return "error: usage"
		return self.order(toks)
	if cmd == "cancel" or cmd == "ship":
		if n != 2: return "error: usage"
		id := toks.get(1, "")
		st := self.status.get_or(id, -1)
		if st < 0: return "error: unknown order {id}"
		if cmd == "cancel":
			if st == 1: return "error: order {id} already shipped"
			if st == 2: return "error: order {id} already cancelled"
			ss := self.skus.get_or(id, [])
			qs := self.qtys.get_or(id, [])
			for i in 0..ss.length():
				k := ss.get(i, "")
				self.stock[k.clone()] = self.stock.get_or(k, 0) + qs.get(i, 0)
			self.status[id.clone()] = 2
			return "ok"
		if st == 1: return "error: order {id} already shipped"
		if st == 2: return "error: order {id} is cancelled"
		self.status[id.clone()] = 1
		return "ok"
	if cmd == "report":
		if n != 1: return "error: usage"
		return self.report()
	return "error: unknown command"

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	data := read_all(stdin())?
	text := data.decode_utf8().ok_or(Error("bad utf8"))?
	var st = State()
	for line in text.split("\n"):
		if line.trim_chars(" ").length() == 0: continue
		print(st.handle(line))
