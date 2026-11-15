# Idiomatic Manuscript

How Manuscript programs are written, in six complete programs. Each one compiles and shows the shape to copy: data in records and enums, behavior in small functions, pipelines for transforming collections, loops for changing state, errors and absence as values, and one owner per value.

## Model data with `type` and `enum`, match every case

A record holds the facts; an enum names the states and carries what each state needs. `match` covers every case, so adding a case makes the compiler point at each function to update. Use a `_:` arm only for "everything else". Transform collections with a pipeline (`xs | .filter(f) | .map(g) | .sum()`); reach for a `for` loop when building a Map or changing a `var`.

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

- A function used as a value (`.filter(is_open)`) is cleaner than a one-use closure.
- A name used after it is stored in a collection is stored as `.clone()` (`spent.add(order.customer.clone(), total)`).
- `get_or(key, default)` reads a Map with a fallback; no `if contains` first.

## Errors are values: `T!` and `?`

A function that can fail returns `T!` (a Result). Inside it, `?` unwraps a success and returns the error early, so the happy path reads straight down. Turn an Optional into a Result with `.ok_or(Error(...))`. Give the error a message that names the input and a `kind` such as `"EINVAL"`. The caller decides: `?` again, `if r.is_error():`, or `.get(default)`. Nothing is thrown and a Result is never dropped.

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
			print(f"total: {result.get(0)}")
```

## One owner: borrow, change with `var`, clone to copy

Reading a value (a plain argument, a comparison, a field read) borrows it. A function that changes its argument says `var` in the declaration and at the call (`add_gift(var cart)`), so changes are visible at both ends. Storing a value in a collection or record moves it; to keep the original, store `.clone()`. `.clone()` is the only copy, so scanning for it shows where data is duplicated.

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

- Error "`x` is moved here but used again": store `x.clone()`, or move it at its last use.
- Error "cannot move `x` out: it is borrowed": a loop variable, a parameter and an element read are borrowed; clone before storing.
- Numbers, booleans and payload-free enums copy; this only matters for text, lists, maps and records.

## Read input as a stream, count with a Map

Standard input, files and sockets are streams. `stdin() | lines | collect(none)?` reads every line into a List, in a function that returns a Result. Count with `counts.add(key.clone(), counts.get_or(key, 0) + 1)`, then sort and slice a copy of the entries.

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
	top := counts.entries().sorted(fn a, b: b.value.compare(a.value)).slice(0, 3).get(none)
	for entry in top:
		print(f"{entry.key} {entry.value}")
```

## Start waiting work together, then collect

A call that waits (reading a file, a request) returns a Promise that is already running. There is no `async`. Start several with `map`, then `wait_all` them; the first failure cancels the rest. Share state between tasks by giving it one owner and sending messages through a pipe, never by sharing a `var` (see servers-and-state.md).

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

## Test next to the code

A `test "name":` block sits in the same file and runs with `ms test`. Test the rules where a mistake costs something, with `expect_equal(actual, expected)?`. Run `ms check --fix`, then `ms verify`, before calling work done.

<!-- complete: idiom-totals.ms -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn shipping(subtotal: Int) Int:
	if subtotal >= 4000:
		return 0
	return 500

fn order_total(prices: List[Int]) Int:
	subtotal := prices.sum()
	return subtotal + shipping(subtotal)

test "small orders pay shipping":
	expect_equal(order_total([1250, 800]), 2550)?

test "big orders ship free":
	expect_equal(order_total([2500, 2500]), 5000)?
```
