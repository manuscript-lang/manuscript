import lines from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"

type State:
	stock: Map[String, Int] = Map[String, Int]()
	price: Map[String, Int] = Map[String, Int]()
	status: Map[String, Int] = Map[String, Int]()
	total: Map[String, Int] = Map[String, Int]()
	items: Map[String, List[String]] = Map[String, List[String]]()
	ids: List[String] = []

fn in_range(c: String, lo: String, hi: String) Bool:
	return c >= lo and c <= hi

fn valid_sku(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not (in_range(c, "A", "Z") or in_range(c, "0", "9") or c == "-"): return false
	return true

fn valid_id(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not (in_range(c, "a", "z") or in_range(c, "0", "9") or c == "-"): return false
	return true

fn parse_num(s: String, lo: Int, hi: Int) Int?:
	n := s.length()
	if n < 1 or n > 7: return none
	for c in s.chars():
		if not in_range(c, "0", "9"): return none
	v := s.parse_int().get(-1)
	if v < lo or v > hi: return none
	return v

fn money(c: Int) String:
	r := c % 100
	rs := if r < 10: "0{r}" else: "{r}"
	return "{c / 100}.{rs}"

fn var State.run(line: String) Unit:
	t := line.split(" ")
	name := t.get(0, "")
	n := t.length()
	if name == "stock":
		if n != 3: return print("error: usage")
		sku := t.get(1, "")
		if not valid_sku(sku): return print("error: bad sku")
		q := parse_num(t.get(2, ""), 1, 100000)
		if q.is_none(): return print("error: bad quantity")
		ns := self.stock.get_or(sku, 0) + q.get(0)
		self.stock[sku.clone()] = ns
		if not self.price.contains(sku): self.price[sku.clone()] = 0
		print("ok {sku} stock={ns}")
	else if name == "price":
		if n != 3: return print("error: usage")
		p := parse_num(t.get(2, ""), 0, 10000000)
		if p.is_none(): return print("error: bad price")
		sku := t.get(1, "")
		if not self.stock.contains(sku): return print("error: unknown sku {sku}")
		self.price[sku.clone()] = p.get(0)
		print("ok")
	else if name == "order":
		if n < 3: return print("error: usage")
		id := t.get(1, "")
		if not valid_id(id): return print("error: bad order id")
		if self.status.contains(id): return print("error: order {id} already exists")
		var skus = List[String]()
		var qtys = List[Int]()
		for i in 2..n:
			tok := t.get(i, "")
			parts := tok.split(":")
			var ok = false
			if parts.length() == 2:
				q := parse_num(parts.get(1, ""), 1, 100000)
				if valid_sku(parts.get(0, "")) and q.is_some():
					ok = true
					skus.append(parts.get(0, ""))
					qtys.append(q.get(0))
			if not ok: return print("error: bad item {tok}")
		var seen = Set[String]()
		for i in 0..skus.length():
			sku := skus.get(i, "")
			q := qtys.get(i, 0)
			if seen.contains(sku): return print("error: duplicate sku {sku}")
			seen.add(sku.clone())
			if not self.stock.contains(sku): return print("error: unknown sku {sku}")
			have := self.stock.get_or(sku, 0)
			if q > have: return print("error: insufficient stock for {sku} (have {have}, need {q})")
		var tot = 0
		var toks = List[String]()
		for i in 0..skus.length():
			sku := skus.get(i, "")
			q := qtys.get(i, 0)
			self.stock[sku.clone()] = self.stock.get_or(sku, 0) - q
			p := self.price.get_or(sku, 0)
			if q >= 10:
				tot += (q * p * 90 + 50) / 100
			else:
				tot += q * p
			toks.append("{sku}:{q}")
		self.status[id.clone()] = 0
		self.total[id.clone()] = tot
		self.items[id.clone()] = toks
		self.ids.append(id.clone())
		print("ok {id} total={money(tot)}")
	else if name == "cancel" or name == "ship":
		if n != 2: return print("error: usage")
		id := t.get(1, "")
		if not self.status.contains(id): return print("error: unknown order {id}")
		st := self.status.get_or(id, 0)
		if st == 1: return print("error: order {id} already shipped")
		if st == 2:
			if name == "cancel": return print("error: order {id} already cancelled")
			return print("error: order {id} is cancelled")
		if name == "ship":
			self.status[id.clone()] = 1
		else:
			self.status[id.clone()] = 2
			for tok in self.items.get_or(id, []):
				parts := tok.split(":")
				sku := parts.get(0, "")
				self.stock[sku.clone()] = self.stock.get_or(sku, 0) + parts.get(1, "0").parse_int().get(0)
		print("ok")
	else if name == "report":
		if n != 1: return print("error: usage")
		skus := self.stock.keys().sorted()
		for sku in skus:
			var reserved = 0
			for id in self.ids:
				if self.status.get_or(id, 0) == 0:
					for tok in self.items.get_or(id, []):
						parts := tok.split(":")
						if parts.get(0, "") == sku:
							reserved += parts.get(1, "0").parse_int().get(0)
			print("{sku} stock={self.stock.get_or(sku, 0)} price={money(self.price.get_or(sku, 0))} reserved={reserved}")
		var a = 0
		var b = 0
		var c = 0
		var rev = 0
		for id in self.ids:
			s := self.status.get_or(id, 0)
			if s == 0: a += 1
			else if s == 1:
				b += 1
				rev += self.total.get_or(id, 0)
			else: c += 1
		print("orders placed={a} shipped={b} cancelled={c}")
		print("revenue={money(rev)}")
	else:
		print("error: unknown command")

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	var st = State()
	for line in lines(stdin()):
		if line.trim_chars(" ").length() == 0: continue
		st.run(line)
