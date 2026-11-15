import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn is_digit(c: String) Bool: c >= "0" and c <= "9"

fn all_in(s: String, upper: Bool) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		ok := is_digit(c) or c == "-" or (upper and c >= "A" and c <= "Z") or (not upper and c >= "a" and c <= "z")
		if not ok: return false
	return true

fn num(s: String) Int:
	if s.length() < 1 or s.length() > 7: return -1
	for c in s.chars():
		if not is_digit(c): return -1
	return s.parse_int().get(-1)

fn qty_of(s: String) Int:
	n := num(s)
	if n < 1 or n > 100000: return -1
	return n

fn money(c: Int) String:
	r := c % 100
	rs := if r < 10: "0{r}" else: "{r}"
	return "{c / 100}.{rs}"

type State:
	stock: Map[String, Int] = Map[String, Int]()
	price: Map[String, Int] = Map[String, Int]()
	status: Map[String, Int] = Map[String, Int]()
	total: Map[String, Int] = Map[String, Int]()
	oskus: Map[String, List[String]] = Map[String, List[String]]()
	oqtys: Map[String, List[Int]] = Map[String, List[Int]]()

fn var State.exec(toks: List[String]) List[String]:
	var out = List[String]()
	cmd := toks.get(0, "")
	n := toks.length()
	if cmd == "stock":
		if n != 3: return ["error: usage"]
		sku := toks.get(1, "")
		if not all_in(sku, true): return ["error: bad sku"]
		q := qty_of(toks.get(2, ""))
		if q < 0: return ["error: bad quantity"]
		ns := self.stock.get_or(sku, 0) + q
		if not self.price.contains(sku): self.price[sku.clone()] = 0
		self.stock[sku.clone()] = ns
		return ["ok {sku} stock={ns}"]
	if cmd == "price":
		if n != 3: return ["error: usage"]
		sku := toks.get(1, "")
		ps := toks.get(2, "")
		p := num(ps)
		if p < 0 or p > 10000000: return ["error: bad price"]
		if not self.stock.contains(sku): return ["error: unknown sku {sku}"]
		self.price[sku.clone()] = p
		return ["ok"]
	if cmd == "order":
		if n < 3: return ["error: usage"]
		id := toks.get(1, "")
		if not all_in(id, false): return ["error: bad order id"]
		if self.status.contains(id): return ["error: order {id} already exists"]
		var skus = List[String]()
		var qtys = List[Int]()
		for i in 2..n:
			t := toks.get(i, "")
			parts := t.split(":")
			if parts.length() != 2: return ["error: bad item {t}"]
			s := parts.get(0, "")
			q := qty_of(parts.get(1, ""))
			if not all_in(s, true) or q < 0: return ["error: bad item {t}"]
			skus.append(s.clone())
			qtys.append(q)
		for i in 0..skus.length():
			s := skus.get(i, "")
			for j in 0..i:
				if skus.get(j, "") == s: return ["error: duplicate sku {s}"]
			if not self.stock.contains(s): return ["error: unknown sku {s}"]
			have := self.stock.get_or(s, 0)
			need := qtys.get(i, 0)
			if need > have: return ["error: insufficient stock for {s} (have {have}, need {need})"]
		var tot = 0
		for i in 0..skus.length():
			s := skus.get(i, "")
			q := qtys.get(i, 0)
			p := self.price.get_or(s, 0)
			self.stock[s.clone()] = self.stock.get_or(s, 0) - q
			if q >= 10:
				tot += (q * p * 90 + 50) / 100
			else:
				tot += q * p
		self.status[id.clone()] = 0
		self.total[id.clone()] = tot
		self.oskus[id.clone()] = skus
		self.oqtys[id.clone()] = qtys
		return ["ok {id} total={money(tot)}"]
	if cmd == "cancel" or cmd == "ship":
		if n != 2: return ["error: usage"]
		id := toks.get(1, "")
		if not self.status.contains(id): return ["error: unknown order {id}"]
		st := self.status.get_or(id, 0)
		if cmd == "ship":
			if st == 1: return ["error: order {id} already shipped"]
			if st == 2: return ["error: order {id} is cancelled"]
			self.status[id.clone()] = 1
			return ["ok"]
		if st == 1: return ["error: order {id} already shipped"]
		if st == 2: return ["error: order {id} already cancelled"]
		self.status[id.clone()] = 2
		skus := self.oskus.get_or(id, List[String]())
		qtys := self.oqtys.get_or(id, List[Int]())
		for i in 0..skus.length():
			s := skus.get(i, "")
			self.stock[s.clone()] = self.stock.get_or(s, 0) + qtys.get(i, 0)
		return ["ok"]
	if cmd == "report":
		if n != 1: return ["error: usage"]
		var names = List[String]()
		for e in self.stock.entries():
			names.append(e.key.clone())
		names.sort()
		var reserved = Map[String, Int]()
		var a = 0
		var b = 0
		var c = 0
		var rev = 0
		for e in self.status.entries():
			if e.value == 0:
				a += 1
				skus := self.oskus.get_or(e.key, List[String]())
				qtys := self.oqtys.get_or(e.key, List[Int]())
				for i in 0..skus.length():
					s := skus.get(i, "")
					reserved[s.clone()] = reserved.get_or(s, 0) + qtys.get(i, 0)
			else if e.value == 1:
				b += 1
				rev += self.total.get_or(e.key, 0)
			else:
				c += 1
		for s in names:
			out.append("{s} stock={self.stock.get_or(s, 0)} price={money(self.price.get_or(s, 0))} reserved={reserved.get_or(s, 0)}")
		out.append("orders placed={a} shipped={b} cancelled={c}")
		out.append("revenue={money(rev)}")
		return out
	return ["error: unknown command"]

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var st = State()
	for line in lines(stdin()):
		if line.trim_chars(" \r").length() == 0: continue
		l := line.trim_end_chars("\r")
		for o in st.exec(l.split(" ")):
			print(o)
