# Mental model

Seven fixed ideas; every rule and error follows from them.

1. **Plain data.** `type` is a record, `enum` is one of several cases with payloads, `interface` is a set of method shapes met by matching methods declared beside a type. Methods live at module scope (`fn Stock.count() Int:`), never in the type body. Add an enum case and `ms check` lists each `match` to update.
2. **One owner.** Int, Float, Bool, Void and payload-free enums copy. Everything else has one owner (binding, field or slot), released at scope end. Reading and passing **borrow**; changing needs `var` at the declaration and the call; storing, returning or a `move` parameter **moves** (the old name is dead); `.clone()` is the only copy. Standard collections take what they store, so storing a borrowed value needs `.clone()`. Decide read, change or take at each signature; "moved here but used again" means clone at the store or reorder.
3. **Failure is a value.** `T!` is `Result[T, Error]`, `T?` is Optional. Postfix `?` unwraps either or returns early. `.ok_or(Error("what, which input", kind: "EINVAL"))` turns absence into an error. A fault (out-of-range `get`, `get()` on an error) is a bug that ends the promise or program; never design around catching it.
4. **Effects are declared.** `ms lint` reports a function that prints, touches files, network, clock, env or randomness unless `// ms: allow_effect std.fs.read` (or a pattern) is above it; `main`, tests and fixtures are exempt. Prefer a pure core plus capabilities (interface values) made in `main`; a test passes a fake. Allow narrowly, at the lowest function that needs it.
5. **Waiting is a value.** A waiting call returns a running `Promise[T]`; `.wait()` takes its result once, `wait_all` several. Dropping an unfinished promise cancels it. A promise reads what it captures; an escaping closure takes it (clone first). State shared by tasks has one owner; others send it events over a `pipe`.
6. **Resources close themselves.** A type with `fn move close() Void!` (files, sockets, stream ends) closes at scope end on every exit, and holders close their parts. A close error becomes the function's error. `x.close()` consumes `x`; call it only to handle that error. Only an owner can close: take a `move` parameter.
7. **Check before run.** The checker proves types, ownership, exhaustiveness and Result handling; `--fix` applies mechanical repairs. Then test, run, `ms verify`.

All of it in one program: failures with named kinds, ownership at each signature, a capability a test fakes.

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
