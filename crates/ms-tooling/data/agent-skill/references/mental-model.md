# Mental model

Manuscript has few ideas, applied everywhere. Learn them once and most compiler messages and API shapes become predictable. This page states each idea, what it forces in your code, and one program that uses all of them.

## 1. Values, not objects

A `type` is a record of fields; an `enum` is one of several cases, each with its own payload; an `interface` is a set of method shapes that any type can satisfy by declaring matching methods beside it. There is no inheritance, no null, no tuple, no implicit conversion between numeric types. Behavior lives in functions and in methods declared at module scope (`fn Stock.count() Int:`), never inside the type body.

Consequence: model a domain by listing its facts as fields and its states as enum cases. Then write `match` over the enum. When a case is added, the checker names every `match` that must change, so the type is the to-do list.

## 2. One owner per value

Int, Float, Bool, Void and payload-free enums copy. Everything else (String, List, Map, Set, records, enums with payloads) has exactly one owner: a binding, a field or a collection slot. The owner releases the value when its scope ends. There is no reference count and no garbage collector.

- **Borrow** is the default. `b := a`, `f(a)`, `for x in xs`, a `match` payload and `xs.get_or(i, d)` all read in place and leave `a` yours. A borrow lasts until its last use; while it lives the owner cannot be changed or moved.
- **Change** is explicit twice: `var` at the declaration (`fn add(var names: List[String])`) and at the call (`add(var names)`). A `fn var` method mutates its receiver and is called plainly (`stock.take(...)`).
- **Move** happens when a value is stored (`xs.append(name)`, a record field, a map entry), returned, or passed to a `move` parameter. The old name is dead afterwards. Standard collections take what they store (`append(move T)`), so storing a borrowed value needs `.clone()`.
- **Clone** is the only copy and costs time and memory. Reach for it last: first try borrowing, moving at the last use, or keeping an index instead of a copy.

Consequence: decide at each signature whether a function reads, changes or takes its argument. The compiler checks the rest. "Moved here but used again" means: clone where it is stored, or restructure so the later use comes first. There is no shared mutable value anywhere, which is why concurrency (section 5) is message passing.

## 3. Failure is a value

`T!` is `Result[T, Error]`; `T?` is an Optional. Both are ordinary values you return, store and match. Postfix `?` unwraps one and, on error or absence, returns from your function, so a happy path reads straight down. Convert between them with `.ok_or(Error("what, which input"))` and `.to_optional()`. `Error` has a message and an optional `kind` code such as `"EINVAL"`.

A fault is different: an out-of-range `xs.get(i)`, `get()` on an error, a failed `close` with nowhere to return its error, a stack overflow. A fault is a bug, not a result: it ends the promise or the program with a report and a non-zero status. Never design around catching one.

Consequence: every call that can fail forces a decision at the call site, and the decision is nearly always `?`. Write the error message so it names the input.

## 4. Effects are declared, capabilities are passed

A function that prints, touches files, uses the network, the clock, the environment or randomness is reported by `ms lint`/`ms verify` unless `// ms: allow_effect std.fs.read` (or a pattern) sits above it. `main`, `test` and fixtures may do anything. The better fix is usually structural: keep the core pure and give it an interface value (a `Logger`, a `Clock`) made by `main`. Then a test passes a fake.

Consequence: effects bubble up through callers, so allow narrowly, at the lowest function that really needs it, and prefer parameters to permissions. Packages declare their effects in `ms.toml`; an application grants them.

## 5. Waiting and sharing

A call that waits (file, network, sleep, your own `promise(fn: ...)`) returns a `Promise[T]` that is already running. Take its result once with `.wait()`; `wait_all` takes several. Dropping an unfinished promise cancels it. A promise reads what it captures and cannot change it, and an escaping closure takes what it captures (clone first to keep your copy).

State that several tasks need has one owner (a promise or a function that holds the `var`). Others send it messages through a `pipe`: a writer per sender, one reader for the owner. A server handler follows the same rule and reports facts to the owner instead of mutating shared state.

Streams are lazy and pull: `lines`, `map`, `filter`, `collect` from `@std/io/streams.ms`. Reading is `for x in stream:` inside a Result function; closing a stream closes its inputs.

## 6. Resources close themselves

Anything with `fn move close() Void!` (files, sockets, stream ends, your own types) closes at scope end on every exit path, in reverse declaration order, and a holder (record, list, map, optional) closes what it holds. A close error becomes the function's error. Calling `close()` yourself is for handling that error: the call moves the value, so scope end does nothing more. A borrowed value cannot be closed; take it with `move` to close it. Flush a write stream (`flush()?`) before its scope ends when you need to see a write failure.

## 7. Everything is checkable before it runs

The checker proves ownership, exhaustiveness, types and Result handling, and its messages say how to fix them. `ms check --fix` applies the mechanical ones. Tests are blocks beside the code. `ms verify` runs the checker, formatter check, lint and tests in one command. So write, check, correct from the message, and only then run.

## All seven in one program

A stock room that takes items out, names its failures, and prices through a capability a test can fake.

<!-- complete: mental-model-stock.ms -->
```manuscript
import expect_equal, expect_true from "@std/test/test.ms"

interface Prices:
	fn cents(sku: String) Int?

type Stock:
	items: Map[String, Int]

enum Outcome:
	Taken(left: Int)
	Refused(reason: String)

fn var Stock.add(sku: String, qty: Int) Void:
	total := self.items.get_or(sku, 0) + qty
	self.items.add(sku.clone(), total)

fn var Stock.take(sku: String, qty: Int) Outcome:
	have := self.items.get_or(sku, 0)
	if have < qty: return Outcome.Refused(f"only {have} of {sku}")

	self.items.add(sku.clone(), have - qty)
	return Outcome.Taken(have - qty)

fn checkout(var stock: Stock, prices: Prices, sku: String, qty: Int) Int!:
	if qty <= 0:
		return error(Error(f"quantity must be positive: {qty}", kind: "EINVAL"))

	price := prices.cents(sku).ok_or(Error(f"no price for {sku}", kind: "ENOENT"))?

	match stock.take(sku, qty):
		Taken(_left):
			return ok(price * qty)
		Refused(reason):
			return error(Error(reason, kind: "EINVAL"))

type Fixed:
	table: Map[String, Int]

fn Fixed.cents(sku: String) Int?:
	return self.table.get(sku)

test "checkout prices through the capability":
	var table = Map[String, Int]()
	table.add("pen", 150)

	prices := Fixed(table)
	var stock = Stock(Map[String, Int]())
	stock.add("pen", 5)
	expect_equal(checkout(var stock, prices, "pen", 2)?, 300)?

	short := checkout(var stock, prices, "pen", 9)
	expect_true(short.is_error())?
	expect_equal(short.err().message, "only 3 of pen")?

	missing := checkout(var stock, prices, "ink", 1)
	expect_equal(missing.err().kind.get_or(""), "ENOENT")?
```
