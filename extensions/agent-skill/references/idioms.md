# Idiomatic Manuscript

How Manuscript programs are written, in thirteen complete programs grouped by what you are building. Each compiles and runs; copy its shape. The habits they share: data in records and enums, behavior in small functions, pipelines to derive values, loops to change state, errors and absence as values, one owner per value, and a test beside the code.

Pick the section for the task: data and reports (1 to 2), failure and ownership (3 to 4), parsers and algorithms (5 to 7), interfaces and generics (8), input, files and JSON (9 to 11), waiting work (12), tests (13).

## 1. Model data with `type` and `enum`, match every case

A record holds the facts; an enum names the states and carries what each state needs. `match` covers every case, so adding a case makes the compiler point at each function to update; use `_:` only for "everything else". Derive values with a pipeline (`xs | .filter(f) | .map(g) | .sum()`); use a `for` loop when building a Map or changing a `var`.

<!-- complete: idiom-orders.ms -->
```manuscript
type Order:
	id Int
	customer String
	cents Int
	status Status = Status.Open

enum Status:
	Open
	Shipped(tracking String)
	Cancelled(reason String)

fn label(status Status) String:
	match status:
		Open:
			return "waiting"
		Shipped(tracking):
			return f"shipped, tracking {tracking}"
		Cancelled(reason):
			return f"cancelled: {reason}"

fn is_open(order Order) Bool:
	match order.status:
		Open:
			return true
		_:
			return false

fn spent_by_customer(orders List[Order]) Map[String, Int]:
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

- A function used as a value (`.filter(is_open)`) is cleaner than a one-use closure.
- `get_or(key, default)` reads a Map with a fallback; no `if contains` first.

## 2. Turn text into records, group, sort, print

Parse each line into a record or `null`, drop the failures with a pipeline, group into a Map, sort the keys, and `join` the output. Report what was skipped instead of failing silently. `if v := optional:` binds the value in the success branch.

<!-- complete: idiom-report.ms -->
```manuscript
type Sale:
	region String
	cents Int

fn money(cents Int) String:
	rest := cents % 100
	pad := if rest < 10: "0" else: ""
	return f"{cents / 100}.{pad}{rest}"

fn parse_sale(line String) Sale?:
	parts := line.split(",")
	if parts.length() != 2:
		return null
	if cents := parts[1].parse_int():
		return Sale(parts[0].clone(), cents)
	return null

fn totals_by_region(sales List[Sale]) Map[String, Int]:
	var totals = Map[String, Int]()
	for sale in sales:
		totals.add(sale.region.clone(), totals.get_or(sale.region, 0) + sale.cents)
	return totals

fn report(totals Map[String, Int]) List[String]:
	regions := totals.keys().sorted(fn a, b: a.compare(b))
	return regions.map(fn region: f"{region}: {money(totals.get_or(region, 0))}")

fn main() Void:
	lines := ["north,1250", "south,800", "north,2505", "bad line", "south,x"]
	sales := lines | .map(parse_sale) | .filter(fn s: s != null) | .map(fn s: s.get())
	skipped := lines.length() - sales.length()
	print(report(totals_by_region(sales)).join("\n"))
	print(f"skipped {skipped} lines")
```

- `sorted(fn a, b: a.compare(b))` sorts a copy; compare Ints, Floats and Strings with `compare`.
- Money and fixed-width output are small helper functions (`money`), not inline arithmetic.

## 3. Errors are values: `T!` and `?`

A function that can fail returns `T!` (a Result). Inside it, `?` unwraps a success and returns the error early, so the happy path reads straight down. Turn an Optional into a Result with `.ok_or(Error(...))`. The message names the input; `kind` is a short code such as `"EINVAL"`. The caller decides: `?` again, `if r.is_error():`, or `.get_or(default)`. Nothing is thrown and a Result is never dropped.

<!-- complete: idiom-lines.ms -->
```manuscript
type Line:
	name String
	quantity Int
	cents Int

fn parse_line(text String) Line!:
	parts := text.split(",")
	if parts.length() != 3:
		return error(Error(f"expected name,quantity,cents: {text}", kind: "EBADMSG"))
	quantity := parts[1].parse_int().ok_or(Error(f"quantity is not a number: {text}", kind: "EINVAL"))?
	if quantity <= 0:
		return error(Error(f"quantity must be positive: {text}", kind: "EINVAL"))
	cents := parts[2].parse_int().ok_or(Error(f"price is not a number: {text}", kind: "EINVAL"))?
	return ok(Line(parts[0].clone(), quantity, cents))

fn total(lines List[String]) Int!:
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

## 4. One owner: borrow, change with `var`, clone to copy

Reading a value (a plain argument, a comparison, a field read) borrows it. A function that changes its argument says `var` in its declaration (`fn add_gift(var cart Cart)`); the call writes `add_gift(cart)`. Storing a value in a collection or record moves it; to keep the original, store `.clone()`. `.clone()` is the only copy, so scanning for it shows where data is duplicated.

<!-- complete: idiom-cart.ms -->
```manuscript
type Cart:
	owner String
	items List[String]

fn summary(cart Cart) String:
	return f"{cart.owner} has {cart.items.length()} items"

fn add_gift(var cart Cart) Void:
	cart.items.append("gift card")

fn archive(cart Cart, var history List[Cart]) Void:
	history.append(cart)

fn main() Void:
	var cart = Cart("Sam", ["pen", "ink"])
	print(summary(cart))
	add_gift(cart)
	var history = List[Cart]()
	archive(cart.clone(), history)
	cart.items.append("notebook")
	print(f"{summary(cart)}; archived {history[0].items.length()}")
```

- "`x` is moved here but used again": store `x.clone()`, or move it at its last use.
- "cannot move `x` out: it is borrowed": a loop variable, a parameter and an element read are borrowed; clone before storing.
- "`chars` borrows `text`, which this position would keep": a call that returns part of its argument (`text.chars()`) is borrowed; store `text.chars().clone()`.
- Numbers, booleans and payload-free enums copy; this only matters for text, lists, maps and records.

## 5. Parse text with a cursor type and an enum tree

A parser is a record holding the input and a position, with `fn var` methods that advance it. Each grammar rule is one method returning `Node!`; the tree is an `enum` and evaluation is a recursive `match`. Loop in a rule for repetition (`while self.peek() == "*"`); recurse for nesting. Interpreters, SQL, markdown, jq and make clones all take this shape: tokenize or index the text, parse to an enum, evaluate with `match`.

<!-- complete: idiom-calc.ms -->
```manuscript
enum Expr:
	Num(value Int)
	Add(left Expr, right Expr)
	Mul(left Expr, right Expr)
	Neg(inner Expr)

fn eval(expr Expr) Int:
	match expr:
		Num(value):
			return value
		Add(left, right):
			return eval(left) + eval(right)
		Mul(left, right):
			return eval(left) * eval(right)
		Neg(inner):
			return -eval(inner)

type Parser:
	chars List[String]
	pos Int

fn var Parser.peek() String:
	return self.chars.get_or(self.pos, "")

fn var Parser.skip_spaces() Void:
	while self.peek() == " ":
		self.pos += 1

fn var Parser.number() Expr!:
	start := self.pos
	while self.peek() >= "0" and self.peek() <= "9" and not self.peek().is_empty():
		self.pos += 1
	digits := self.chars.slice(start, self.pos) or [].join("")
	value := digits.parse_int().ok_or(Error(f"expected a number at {start}", kind: "EINVAL"))?
	return ok(Expr.Num(value))

fn var Parser.atom() Expr!:
	self.skip_spaces()
	if self.peek() == "-":
		self.pos += 1
		inner := self.atom()?
		return ok(Expr.Neg(inner))
	if self.peek() == "(":
		self.pos += 1
		inner := self.sum()?
		self.skip_spaces()
		if self.peek() != ")":
			return error(Error(f"expected ) at {self.pos}", kind: "EINVAL"))
		self.pos += 1
		return ok(inner)
	return self.number()

fn var Parser.product() Expr!:
	var left = self.atom()?
	self.skip_spaces()
	while self.peek() == "*":
		self.pos += 1
		right := self.atom()?
		left = Expr.Mul(left, right)
		self.skip_spaces()
	return ok(left)

fn var Parser.sum() Expr!:
	var left = self.product()?
	while self.peek() == "+":
		self.pos += 1
		right := self.product()?
		left = Expr.Add(left, right)
	return ok(left)

fn calculate(text String) Int!:
	var parser = Parser(text.chars().clone(), 0)
	expr := parser.sum()?
	return ok(eval(expr))

fn main() Void:
	for text in ["1 + 2 * 3", "-(4 + 5) * 2", "2 *"]:
		result := calculate(text)
		if result.is_error():
			print(f"{text}: error {result.err().message}")
		else:
			print(f"{text} = {result.get_or(0)}")
```

- Rebinding a changing value is `var left = ...` then `left = Expr.Mul(left, right)`; `var x := e` is not valid.
- `self.chars.get_or(self.pos, "")` reads past the end safely; compare the empty string to detect the end.

## 6. Algorithms: grids, queues, visited sets

Breadth-first search is a `List` used as a queue with a `head` index, a `Map` or `Set` of visited keys, and an Optional result. Key a visited set by a string such as `f"{row},{col}"`. A record with two Ints is the point type. Return `null` for "no path" and let the caller handle it with `if steps := shortest(...)`. Dynamic programming is a `var` List of the right length updated in a loop.

<!-- complete: idiom-bfs.ms -->
```manuscript
type Point:
	row Int
	col Int

fn neighbors(grid List[String], at Point) List[Point]:
	var found = List[Point]()
	for step in [Point(-1, 0), Point(1, 0), Point(0, -1), Point(0, 1)]:
		next := Point(at.row + step.row, at.col + step.col)
		line := grid.get_or(next.row, "")
		if next.col >= 0 and next.col < line.length() and line.chars().get_or(next.col, "#") != "#":
			found.append(next)
	return found

fn shortest(grid List[String], start Point, goal Point) Int?:
	var distance = Map[String, Int]()
	var queue = [start.clone()]
	var head = 0
	distance.add(f"{start.row},{start.col}", 0)
	while head < queue.length():
		at := queue[head].clone()
		head += 1
		steps := distance.get_or(f"{at.row},{at.col}", 0)
		if at.row == goal.row and at.col == goal.col:
			return steps
		for next in neighbors(grid, at):
			key := f"{next.row},{next.col}"
			if not distance.contains(key):
				distance.add(key, steps + 1)
				queue.append(next)
	return null

fn main() Void:
	grid := ["S..#", ".#..", "...G"]
	if steps := shortest(grid, Point(0, 0), Point(2, 3)):
		print(f"shortest path: {steps}")
	else:
		print("no path")
```

## 7. A command processor: state in a record, rules in `fn var` methods

Read commands from stdin, keep the state in one record, and give each command a small `fn var` method that returns the reply line. Dispatch with `match` on the command word; check the token count and number syntax first and return `error: ...` lines before changing anything. Call it as `run_command(var shop, line)`.

<!-- complete: idiom-shop.ms -->
```manuscript
import stdin from "@std/io/io.ms"
import collect from "@std/io/streams.ms"
import lines from "@std/io/steps.ms"

type Shop:
	stock Map[String, Int]
	log List[String]

fn var Shop.add(sku String, qty Int) String:
	total := self.stock.get_or(sku, 0) + qty
	self.stock.add(sku.clone(), total)
	return f"ok {sku} stock={total}"

fn var Shop.take(sku String, qty Int) String:
	have := self.stock.get_or(sku, 0)
	if qty > have:
		return f"error: only {have} of {sku}"
	self.stock.add(sku.clone(), have - qty)
	return f"ok {sku} stock={have - qty}"

fn run_command(var shop Shop, line String) String:
	words := line.split(" ")
	qty := words.get_or(2, "").parse_int()
	if words.length() != 3 or qty == null:
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
	text := stdin() | lines | collect(null)?
	for line in text.filter(fn l: not l.is_empty()):
		print(run_command(shop, line))
```

- `match` on a String works; the `_:` arm catches unknown commands.
- A method that only reads is `fn Shop.name()`; one that changes the receiver is `fn var Shop.add()`.

## 8. Interfaces and generics

An `interface` lists the operations a caller depends on; a type satisfies it by having methods with those signatures, with no `implements`. Generic functions take bounds: `T: Clonable` lets the body keep a copy, `T: Equal`, `T: Comparable`, `T: Hashable` for equality, order and map keys.

<!-- complete: idiom-shapes.ms -->
```manuscript
interface Shape:
	fn area() Float
	fn name() String

type Rect:
	width Float
	height Float

type Circle:
	radius Float

fn Rect.area() Float: self.width * self.height
fn Rect.name() String: "rect"
fn Circle.area() Float: 3.0 * self.radius * self.radius
fn Circle.name() String: "circle"

fn largest[T Clonable](items List[T], score fn(T) Float) T?:
	var best T? = null
	var best_score = -1.0
	for item in items:
		s := score(item)
		if s > best_score:
			best_score = s
			best = item.clone()
	return best

fn describe(shape Shape) String:
	return f"{shape.name()} with area {shape.area()}"

fn main() Void:
	print(describe(Rect(2.0, 3.0)))
	print(describe(Circle(1.0)))
	rects := [Rect(2.0, 3.0), Rect(4.0, 1.5), Rect(1.0, 1.0)]
	if big := largest(rects, fn r: r.area()):
		print(f"largest: {big.width} x {big.height}")
```

## 9. Read input as a stream, count with a Map

Standard input, files and sockets are streams. `stdin() | lines | collect(null)?` reads every line into a List, in a function that returns a Result. Count with `counts.add(key.clone(), counts.get_or(key, 0) + 1)`, then sort and slice the entries.

<!-- complete: idiom-words.ms -->
```manuscript
import stdin from "@std/io/io.ms"
import collect from "@std/io/streams.ms"
import lines from "@std/io/steps.ms"

fn word_counts(text List[String]) Map[String, Int]:
	var counts = Map[String, Int]()
	for line in text:
		for word in line.split(" ").filter(fn w: not w.is_empty()):
			counts.add(word.clone(), counts.get_or(word, 0) + 1)
	return counts

fn main() Void!:
	text := stdin() | lines | collect(null)?
	counts := word_counts(text)
	top := counts.entries().sorted(fn a, b: b.value.compare(a.value)).slice(0, 3) or null
	for entry in top:
		print(f"{entry.key} {entry.value}")
```

## 10. A command-line tool: arguments, a file, typed JSON

`arguments()` returns the program arguments; `.first().ok_or(Error("usage: ..."))?` turns a missing one into a usage error. `read_file(path, max_bytes: n).wait()?` reads bytes; `.decode_utf8()` returns an Optional. `parse[Config](text)` reads typed JSON (missing fields take their defaults); `stringify(config)?` writes it back. `main` returns `Void!`, so a failure prints the error and exits nonzero.

<!-- complete: idiom-config.ms -->
```manuscript
import arguments from "@std/os/env.ms"
import read_file from "@std/os/fs.ms"
import parse, stringify from "@std/data/json.ms"

type Config:
	name String
	retries Int = 3
	tags List[String] = []

fn load(path String) Config!:
	bytes := read_file(path, max_bytes: 65536).wait()?
	text := bytes.decode_utf8().ok_or(Error(f"{path} is not UTF-8", kind: "EBADMSG"))?
	return parse[Config](text)

fn main() Void!:
	path := arguments().first().ok_or(Error("usage: config <file.json>", kind: "EINVAL"))?
	config := load(path)?
	print(f"{config.name}: {config.retries} retries, {config.tags.length()} tags")
	print(stringify(config)?)
```

## 11. Files close themselves

A value that owns a resource (a file, a socket) closes when its scope ends, on every path including `?` and `return error(...)`. There is no `close` to forget; bind it with `file := open(path)?` and read from `file.reader()?`.

<!-- complete: idiom-count.ms -->
```manuscript
import open from "@std/os/fs.ms"
import collect from "@std/io/streams.ms"
import lines from "@std/io/steps.ms"

fn count_orders(path String) Int!:
	file := open(path)?
	rows := collect(file.reader()? | lines)?
	if rows.is_empty():
		return error(Error(f"{path} is empty", kind: "EBADMSG"))
	return ok(rows.length() - 1)

fn main() Void!:
	count := count_orders("orders.csv")?
	print(f"{count} orders")
```

## 12. Start waiting work together, then collect

A call that waits (reading a file, a request) returns a Promise that is already running. There is no `async`. Start several with `map`, then `wait_all` them; the first failure cancels the rest. Share state between tasks by giving it one owner and sending messages through a pipe, never by sharing a `var` (see servers-and-state.md).

<!-- complete: idiom-rows.ms -->
```manuscript
import read_file from "@std/os/fs.ms"
import wait_all from "@std/concurrency/promise.ms"

fn count_rows(text String) Int:
	return text.split("\n").filter(fn line: not line.is_empty()).length()

fn run(paths List[String]) Int!:
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

## 13. Test next to the code

A `test "name":` block sits in the same file and runs with `ms test`. Test the rules where a mistake costs something, with `expect_equal(actual, expected)?`. Run `ms check --fix`, then `ms verify`, before calling work done.

<!-- complete: idiom-totals.ms -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn shipping(subtotal Int) Int:
	if subtotal >= 4000:
		return 0
	return 500

fn order_total(prices List[Int]) Int:
	subtotal := prices.sum()
	return subtotal + shipping(subtotal)

test "small orders pay shipping":
	expect_equal(order_total([1250, 800]), 2550)?

test "big orders ship free":
	expect_equal(order_total([2500, 2500]), 5000)?
```
