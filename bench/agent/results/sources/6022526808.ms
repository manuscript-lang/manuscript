import (
	stdin from "@std/io/io.ms",
	lines from "@std/io/streams.ms",
)

// Order status codes.
PLACED := 0
SHIPPED := 1
CANCELLED := 2

// True when every scalar is an uppercase letter, digit or '-'.
fn is_sku(s: String) Bool:
	if s.is_empty(): return false
	return s.scalar_values().all(
		fn c: ((c >= 65 and c <= 90) or (c >= 48 and c <= 57) or c == 45)
	)

// True when every scalar is a lowercase letter, digit or '-'.
fn is_order_id(s: String) Bool:
	if s.is_empty(): return false
	return s.scalar_values().all(
		fn c: ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 45)
	)

// Parses a 1..7 digit number within [lo, hi]; returns -1 when invalid.
fn parse_num(s: String, lo: Int, hi: Int) Int:
	v := s.scalar_values()
	if v.length() < 1 or v.length() > 7: return -1

	var n = 0

	for c in v:
		if c < 48 or c > 57: return -1

		n = n * 10 + (c - 48)

	if n < lo or n > hi: return -1

	return n

// Formats cents as dollars with two decimals.
fn money(c: Int) String:
	r := c % 100
	frac := if r < 10: "0{r}" else: "{r}"
	return "{c / 100}.{frac}"

type Shop:
	stock: Map[String, Int]
	price: Map[String, Int]
	skus: List[String]
	status: Map[String, Int]
	totals: Map[String, Int]
	order_skus: Map[String, List[String]]
	order_qtys: Map[String, List[Int]]
	order_ids: List[String]

impl Shop:
	fn line_cost(qty: Int, cents: Int) Int:
		if qty >= 10: return (qty * cents * 90 + 50) / 100
		return qty * cents

	var fn add_stock(args: List[String]) String:
		sku := args[1]
		if not is_sku(sku): return "error: bad sku"

		qty := parse_num(args[2], 1, 100000)
		if qty < 0: return "error: bad quantity"

		if not self.stock.contains(sku):
			self.stock[sku.clone()] = 0
			self.price[sku.clone()] = 0
			self.skus.append(sku.clone())

		self.stock[sku.clone()] = self.stock[sku] + qty
		return "ok {sku} stock={self.stock[sku]}"

	var fn set_price(args: List[String]) String:
		cents := parse_num(args[2], 0, 10000000)
		if cents < 0: return "error: bad price"

		sku := args[1]
		if not self.stock.contains(sku): return "error: unknown sku {sku}"

		self.price[sku.clone()] = cents
		return "ok"

	var fn place_order(args: List[String]) String:
		id := args[1]
		if not is_order_id(id): return "error: bad order id"

		// Parse every item first; the first malformed token wins.
		var skus = List[String]()
		var qtys = List[Int]()

		for i in 2..args.length():
			parts := args[i].split(":")
			if parts.length() != 2 or not is_sku(parts[0]):
				return "error: bad item {args[i]}"

			qty := parse_num(parts[1], 1, 100000)
			if qty < 0: return "error: bad item {args[i]}"

			skus.append(parts[0].clone())
			qtys.append(qty)

		if self.status.contains(id): return "error: order {id} already exists"

		// Examine items in the order given; the first problem wins.
		for i in 0..skus.length():
			sku := skus[i]
			for j in 0..i:
				if skus[j] == sku: return "error: duplicate sku {sku}"
			if not self.stock.contains(sku): return "error: unknown sku {sku}"
			if qtys[i] > self.stock[sku]:
				return "error: insufficient stock for {sku} (have {self.stock[sku]}, need {qtys[i]})"

		var total = 0

		for i in 0..skus.length():
			sku := skus[i]
			total += self.line_cost(qtys[i], self.price[sku])
			self.stock[sku.clone()] = self.stock[sku] - qtys[i]

		self.status[id.clone()] = PLACED
		self.totals[id.clone()] = total
		self.order_skus[id.clone()] = skus
		self.order_qtys[id.clone()] = qtys
		self.order_ids.append(id.clone())
		return "ok {id} total={money(total)}"

	var fn cancel(args: List[String]) String:
		id := args[1]
		if not self.status.contains(id): return "error: unknown order {id}"

		st := self.status[id]
		if st == SHIPPED: return "error: order {id} already shipped"
		if st == CANCELLED: return "error: order {id} already cancelled"

		self.status[id.clone()] = CANCELLED

		skus := self.order_skus[id]
		qtys := self.order_qtys[id]
		for i in 0..skus.length():
			self.stock[skus[i].clone()] = self.stock[skus[i]] + qtys[i]
		return "ok"

	var fn ship(args: List[String]) String:
		id := args[1]
		if not self.status.contains(id): return "error: unknown order {id}"

		st := self.status[id]
		if st == SHIPPED: return "error: order {id} already shipped"
		if st == CANCELLED: return "error: order {id} is cancelled"

		self.status[id.clone()] = SHIPPED
		return "ok"

	fn report() String:
		var out = List[String]()

		for sku in self.skus.sorted():
			var reserved = 0

			for id in self.order_ids:
				if self.status[id] == PLACED:
					skus := self.order_skus[id]
					qtys := self.order_qtys[id]
					for i in 0..skus.length():
						if skus[i] == sku: reserved += qtys[i]

			out.append(
				"{sku} stock={self.stock[sku]} price={money(self.price[sku])} reserved={reserved}"
			)

		var placed = 0
		var shipped = 0
		var cancelled = 0
		var revenue = 0

		for id in self.order_ids:
			st := self.status[id]

			if st == PLACED: placed += 1
			else if st == SHIPPED:
				shipped += 1
				revenue += self.totals[id]
			else: cancelled += 1

		out.append("orders placed={placed} shipped={shipped} cancelled={cancelled}")
		out.append("revenue={money(revenue)}")
		return out.join("\n")

	var fn handle(line: String) String:
		args := line.split(" ")
		cmd := args[0]
		n := args.length()

		if cmd == "stock":
			if n != 3: return "error: usage"
			return self.add_stock(args)
		else if cmd == "price":
			if n != 3: return "error: usage"
			return self.set_price(args)
		else if cmd == "order":
			if n < 3: return "error: usage"
			return self.place_order(args)
		else if cmd == "cancel":
			if n != 2: return "error: usage"
			return self.cancel(args)
		else if cmd == "ship":
			if n != 2: return "error: usage"
			return self.ship(args)
		else if cmd == "report":
			if n != 1: return "error: usage"
			return self.report()

		return "error: unknown command"

export fn main() Int:
	var shop = Shop(
		stock: Map[String, Int](), price: Map[String, Int](), skus: List[String](),
		status: Map[String, Int](), totals: Map[String, Int](),
		order_skus: Map[String, List[String]](), order_qtys: Map[String, List[Int]](),
		order_ids: List[String]()
	)
	var input = lines(stdin())

	while true:
		next := input.next().get()

		if line := next:
			if line.scalar_values().all(fn c: c == 32): continue

			print(shop.handle(line))
		else:
			break

	return 0
