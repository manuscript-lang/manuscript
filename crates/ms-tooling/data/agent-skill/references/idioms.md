# Idioms

Ten complete programs that compile and run; copy the shape.

## 1. Data: `type`, `enum`, flat `match`, pipelines

Facts in a record, states in an enum, `match` covers every case (`_:` only for "the rest"). Derive with a pipeline; use a `for` loop to build a Map. A named function beats a one-use closure.

<!-- complete: idiom-orders.ms -->
```manuscript
type Order:
	id: Int
	customer: String
	cents: Int
	status: Status = Status.Open

enum Status:
	Open
	Shipped(tracking: String)
	Cancelled(reason: String)

fn label(status: Status) String:
	match status:
		Open:
			return "waiting"
		Shipped(tracking):
			return f"shipped, tracking {tracking}"
		Cancelled(reason):
			return f"cancelled: {reason}"

fn is_open(order: Order) Bool:
	match order.status:
		Open:
			return true
		_:
			return false

fn spent_by_customer(orders: List[Order]) Map[String, Int]:
	var spent = Map[String, Int]()
	for order in orders:
		total := spent.get_or(order.customer, 0) + order.cents
		spent.add(order.customer.clone(), total)
	return spent

fn main() Void:
	orders := [
		Order(1, "Sam", 1250),
		Order(2, "Ada", 4000, status: Status.Shipped("ZX81")),
		Order(3, "Sam", 3100, status: Status.Cancelled("out of stock")),
	]
	open_cents := orders | .filter(is_open) | .map(fn o: o.cents) | .sum()
	spent := spent_by_customer(orders)
	for order in orders:
		print(f"#{order.id} {order.customer}: {label(order.status)}")
	print(f"open: {open_cents}, Sam: {spent.get_or("Sam", 0)}")
```

## 2. Failure: `T!`, `?`, `ok_or`

`?` unwraps or returns the error; the message names the input; `kind` is a short code.

<!-- complete: idiom-lines.ms -->
```manuscript
type Line:
	name: String
	quantity: Int
	cents: Int

fn parse_line(text: String) Line!:
	parts := text.split(",")
	if parts.length() != 3:
		return error(Error(f"expected name,quantity,cents: {text}", kind: "EBADMSG"))
	quantity := parts[1].parse_int().ok_or(Error(f"quantity is not a number: {text}", kind: "EINVAL"))?
	if quantity <= 0:
		return error(Error(f"quantity must be positive: {text}", kind: "EINVAL"))
	cents := parts[2].parse_int().ok_or(Error(f"price is not a number: {text}", kind: "EINVAL"))?
	return ok(Line(parts[0].clone(), quantity, cents))

fn total(lines: List[String]) Int!:
	var sum = 0
	for text in lines:
		line := parse_line(text)?
		sum += line.quantity * line.cents
	return ok(sum)

fn main() Void:
	for input in [["pen,2,150", "ink,1,899"], ["pen,2,150", "ink,0,899"]]:
		result := total(input)
		if result.is_error():
			print(f"bad: {result.err().message}")
		else:
			print(f"total: {result.get_or(0)}")
```

## 3. Ownership: borrow, `var`, `.clone()`

Reading borrows, changing needs `var` twice, storing a borrowed value needs `.clone()`.

<!-- complete: idiom-cart.ms -->
```manuscript
type Cart:
	owner: String
	items: List[String]

fn summary(cart: Cart) String:
	return f"{cart.owner} has {cart.items.length()} items"

fn add_gift(var cart: Cart) Void:
	cart.items.append("gift card")

fn archive(cart: Cart, var history: List[Cart]) Void:
	history.append(cart)

fn main() Void:
	var cart = Cart("Sam", ["pen", "ink"])
	print(summary(cart))
	add_gift(var cart)
	var history = List[Cart]()
	archive(cart.clone(), var history)
	cart.items.append("notebook")
	print(f"{summary(cart)}; archived {history[0].items.length()}")
```

## 4. Interfaces and generics

Interfaces are met by method shape. Bound a generic (`T: Auditable`); lists are invariant, so take `List[T]`.

<!-- complete: idiom-shapes.ms -->
```manuscript
interface Shape:
	fn area() Float
	fn name() String

type Rect:
	width: Float
	height: Float

type Circle:
	radius: Float

fn Rect.area() Float: self.width * self.height
fn Rect.name() String: "rect"
fn Circle.area() Float: 3.0 * self.radius * self.radius
fn Circle.name() String: "circle"

fn largest[T: Clonable](items: List[T], score: fn(T) Float) T?:
	var best: T? = none
	var best_score = -1.0
	for item in items:
		s := score(item)
		if s > best_score:
			best_score = s
			best = item.clone()
	return best

fn describe(shape: Shape) String:
	return f"{shape.name()} with area {shape.area()}"

fn main() Void:
	print(describe(Rect(2.0, 3.0)))
	print(describe(Circle(1.0)))
	rects := [Rect(2.0, 3.0), Rect(4.0, 1.5), Rect(1.0, 1.0)]
	if big := largest(rects, fn r: r.area()):
		print(f"largest: {big.width} x {big.height}")
```

## 5. Streams: read input, count with a Map

`for line in stream | lines:` in a Result function; `get_or(k, 0) + 1` counts.

<!-- complete: idiom-words.ms -->
```manuscript
import stdin from "@std/io/io.ms"
import lines, collect from "@std/io/streams.ms"

fn word_counts(text: List[String]) Map[String, Int]:
	var counts = Map[String, Int]()
	for line in text:
		for word in line.split(" ").filter(fn w: not w.is_empty()):
			counts.add(word.clone(), counts.get_or(word, 0) + 1)
	return counts

fn main() Void!:
	text := stdin() | lines | collect(none)?
	counts := word_counts(text)
	top := counts.entries().sorted(fn a, b: b.value.compare(a.value)).slice(0, 3).get_or(none)
	for entry in top:
		print(f"{entry.key} {entry.value}")
```

## 6. A CLI: arguments, a file, typed JSON

`parse[Config](text)` and `stringify` map JSON to a record; `main` returns `Void!` so errors exit 1.

<!-- complete: idiom-config.ms -->
```manuscript
import arguments from "@std/os/env.ms"
import read_file from "@std/os/fs.ms"
import parse, stringify from "@std/data/json.ms"

type Config:
	name: String
	retries: Int = 3
	tags: List[String] = []

fn load(path: String) Config!:
	bytes := read_file(path, max_bytes: 65536).wait()?
	text := bytes.decode_utf8().ok_or(Error(f"{path} is not UTF-8", kind: "EBADMSG"))?
	return parse[Config](text)

fn main() Void!:
	path := arguments().first().ok_or(Error("usage: config <file.json>", kind: "EINVAL"))?
	config := load(path)?
	print(f"{config.name}: {config.retries} retries, {config.tags.length()} tags")
	print(stringify(config)?)
```

## 7. Resources close at scope end

No `close()` to forget, on every exit path. Call `close()` only to handle its error; it consumes the value.

<!-- complete: idiom-count.ms -->
```manuscript
import open from "@std/os/fs.ms"
import lines, collect from "@std/io/streams.ms"

fn count_orders(path: String) Int!:
	file := open(path)?
	rows := collect(file.reader()? | lines)?
	if rows.is_empty():
		return error(Error(f"{path} is empty", kind: "EBADMSG"))
	return ok(rows.length() - 1)

fn main() Void!:
	count := count_orders("orders.csv")?
	print(f"{count} orders")
```

## 8. Waiting work: start together, collect

Waiting calls return running promises; `wait_all` stops at the first failure. Shared state: [Servers and state](servers-and-state.md).

<!-- complete: idiom-rows.ms -->
```manuscript
import read_file from "@std/os/fs.ms"
import wait_all from "@std/concurrency/promise.ms"

fn count_rows(text: String) Int:
	return text.split("\n").filter(fn line: not line.is_empty()).length()

fn run(paths: List[String]) Int!:
	reads := paths.map(fn path: read_file(path))
	files := wait_all(reads)?
	var rows = 0
	for file in files:
		text := file.decode_utf8().ok_or(Error("not UTF-8", kind: "EBADMSG"))?
		rows += count_rows(text)
	return ok(rows)

fn main() Void!:
	rows := run(["a.csv", "b.csv"])?
	print(f"{rows} rows")
```

## 9. Change records you hold: index into the list, or take a clone out and put it back

Edit in place with `self.orders[i].field = v`, or `for_each(fn var o: ...)`. For a Map, clone the value out, change the clone, `add` it back. Do not bind `o := self.orders[i]` and then change `self.orders` (that is the borrow error).

<!-- complete: idiom-edit-records.ms -->
```manuscript
enum Status:
	Open
	Shipped

type Order:
	id: Int
	qty: Int
	status: Status = Status.Open

type Shop:
	orders: List[Order]
	by_id: Map[Int, Order]

fn var Shop.ship(id: Int) Bool:
	for i in 0..self.orders.length():
		if self.orders[i].id == id:
			self.orders[i].status = Status.Shipped
			return true

	return false

fn var Shop.ship_map(id: Int) Bool:
	if found := self.by_id.get(id):
		var order = found.clone()
		order.status = Status.Shipped
		self.by_id.add(id, order)
		return true

	return false

fn var Shop.bump_all() Void:
	self.orders.for_each(fn var o: o.qty += 1)

fn main() Void:
	var shop = Shop([Order(1, 2)], Map[Int, Order]())
	print(shop.ship(1))
	shop.bump_all()
	print(shop.orders[0].qty)
```

## 10. Mutable state: a record, rules in `fn var` methods, a command loop

Keep the state in one record, give each command a small `fn var` method that returns the reply, check input before changing anything, and call `run_command(var shop, line)`.

<!-- complete: idiom-shop.ms -->
```manuscript
import stdin from "@std/io/io.ms"
import lines, collect from "@std/io/streams.ms"

type Shop:
	stock: Map[String, Int]
	log: List[String]

fn var Shop.add(sku: String, qty: Int) String:
	total := self.stock.get_or(sku, 0) + qty
	self.stock.add(sku.clone(), total)
	return f"ok {sku} stock={total}"

fn var Shop.take(sku: String, qty: Int) String:
	have := self.stock.get_or(sku, 0)
	if qty > have:
		return f"error: only {have} of {sku}"
	self.stock.add(sku.clone(), have - qty)
	return f"ok {sku} stock={have - qty}"

fn run_command(var shop: Shop, line: String) String:
	words := line.split(" ")
	qty := words.get_or(2, "").parse_int()
	if words.length() != 3 or qty.is_none():
		return "error: usage: add|take <sku> <qty>"
	match words[0]:
		"add":
			return shop.add(words[1], qty.get())
		"take":
			return shop.take(words[1], qty.get())
		_:
			return f"error: unknown command {words[0]}"

fn main() Void!:
	var shop = Shop(Map[String, Int](), [])
	text := stdin() | lines | collect(none)?
	for line in text.filter(fn l: not l.is_empty()):
		print(run_command(var shop, line))
```
