import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Order:
	skus: List[String]
	qtys: List[Int]
	total: Int
	status: Int

type State:
	stock: Map[String, Int]
	price: Map[String, Int]
	orders: Map[String, Order]
	order_ids: List[String]

fn all_in(s: String, set: String) Bool:
	if s.is_empty(): return false
	for c in s.chars():
		if not set.contains(c): return false
	return true

fn valid_sku(s: String) Bool: all_in(s, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")

fn valid_id(s: String) Bool: all_in(s, "abcdefghijklmnopqrstuvwxyz0123456789-")

fn number(s: String) Int:
	if s.length() > 7 or not all_in(s, "0123456789"): return -1
	return s.parse_int().get(-1)

fn qty_of(s: String) Int:
	n := number(s)
	if n < 1 or n > 100000: return -1
	return n

fn money(c: Int) String:
	cents := c % 100
	pad := if cents < 10: "0" else: ""
	return "{c / 100}.{pad}{cents}"

fn var State.handle(line: String) List[String]:
	var out = List[String]()
	t := line.split(" ")
	n := t.length()
	cmd := t.get(0, "")
	if cmd == "stock":
		if n != 3:
			out.append("error: usage")
			return out
		sku := t.get(1, "")
		if not valid_sku(sku):
			out.append("error: bad sku")
			return out
		q := qty_of(t.get(2, ""))
		if q < 0:
			out.append("error: bad quantity")
			return out
		ns := self.stock.get_or(sku, 0) + q
		self.stock[sku.clone()] = ns
		if not self.price.contains(sku):
			self.price[sku.clone()] = 0
		out.append("ok {sku} stock={ns}")
	else if cmd == "price":
		if n != 3:
			out.append("error: usage")
			return out
		sku := t.get(1, "")
		p := number(t.get(2, ""))
		if p < 0 or p > 10000000:
			out.append("error: bad price")
			return out
		if not self.stock.contains(sku):
			out.append("error: unknown sku {sku}")
			return out
		self.price[sku.clone()] = p
		out.append("ok")
	else if cmd == "order":
		if n < 3:
			out.append("error: usage")
			return out
		id := t.get(1, "")
		if not valid_id(id):
			out.append("error: bad order id")
			return out
		if self.orders.contains(id):
			out.append("error: order {id} already exists")
			return out
		var skus = List[String]()
		var qtys = List[Int]()
		for i in 2..n:
			tok := t.get(i, "")
			parts := tok.split(":")
			q := if parts.length() == 2: qty_of(parts.get(1, "")) else: -1
			if parts.length() != 2 or not valid_sku(parts.get(0, "")) or q < 0:
				out.append("error: bad item {tok}")
				return out
			skus.append(parts.get(0, ""))
			qtys.append(q)
		var seen = Set[String]()
		for i in 0..skus.length():
			sku := skus.get(i, "")
			q := qtys.get(i, 0)
			if seen.contains(sku):
				out.append("error: duplicate sku {sku}")
				return out
			seen.add(sku.clone())
			if not self.stock.contains(sku):
				out.append("error: unknown sku {sku}")
				return out
			have := self.stock.get_or(sku, 0)
			if q > have:
				out.append("error: insufficient stock for {sku} (have {have}, need {q})")
				return out
		var total = 0
		for i in 0..skus.length():
			sku := skus.get(i, "")
			q := qtys.get(i, 0)
			p := self.price.get_or(sku, 0)
			if q >= 10:
				total += (q * p * 90 + 50) / 100
			else:
				total += q * p
			self.stock[sku.clone()] = self.stock.get_or(sku, 0) - q
		self.orders[id.clone()] = Order(skus, qtys, total, 0)
		self.order_ids.append(id.clone())
		out.append("ok {id} total={money(total)}")
	else if cmd == "cancel" or cmd == "ship":
		if n != 2:
			out.append("error: usage")
			return out
		id := t.get(1, "")
		if not self.orders.contains(id):
			out.append("error: unknown order {id}")
			return out
		var o = self.orders.get(id).get(Order(List[String](), List[Int](), 0, 0))
		st := o.status
		if st == 1:
			out.append("error: order {id} already shipped")
			return out
		if st == 2:
			if cmd == "cancel":
				out.append("error: order {id} already cancelled")
			else:
				out.append("error: order {id} is cancelled")
			return out
		if cmd == "ship":
			self.orders[id.clone()] = Order(o.skus.clone(), o.qtys.clone(), o.total, 1)
		else:
			for i in 0..o.skus.length():
				sku := o.skus.get(i, "")
				self.stock[sku.clone()] = self.stock.get_or(sku, 0) + o.qtys.get(i, 0)
			self.orders[id.clone()] = Order(o.skus.clone(), o.qtys.clone(), o.total, 2)
		out.append("ok")
	else if cmd == "report":
		if n != 1:
			out.append("error: usage")
			return out
		var reserved = Map[String, Int]()
		var placed = 0
		var shipped = 0
		var cancelled = 0
		var revenue = 0
		for id in self.order_ids:
			o := self.orders.get(id).get(Order(List[String](), List[Int](), 0, 0))
			if o.status == 0:
				placed += 1
				for i in 0..o.skus.length():
					sku := o.skus.get(i, "")
					reserved[sku.clone()] = reserved.get_or(sku, 0) + o.qtys.get(i, 0)
			else if o.status == 1:
				shipped += 1
				revenue += o.total
			else:
				cancelled += 1
		for sku in self.stock.keys().sorted():
			out.append("{sku} stock={self.stock.get_or(sku, 0)} price={money(self.price.get_or(sku, 0))} reserved={reserved.get_or(sku, 0)}")
		out.append("orders placed={placed} shipped={shipped} cancelled={cancelled}")
		out.append("revenue={money(revenue)}")
	else:
		out.append("error: unknown command")
	return out

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var st = State(Map[String, Int](), Map[String, Int](), Map[String, Order](), List[String]())
	for line in lines(stdin()):
		l := line.trim_end_chars("\r")
		if l.trim_chars(" ").is_empty(): continue
		for o in st.handle(l):
			print(o)
