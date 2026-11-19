# Testing

`check` proves types and ownership; only tests and runs prove behavior.

- `test "name":` blocks sit beside the code; no `main` needed. Assertions from `@std/test/test.ms` return Results: end each with `?` (a bare call is a check error).
- `expect_equal(actual, expected)?` shows both values; compare whole strings and lists. Also `expect_true`, `expect_false`, `expect_not_equal`, `expect_close`, `expect_some`, `expect_ok`, `expect_error` (returns the cause), `expect_none`, `expect_fault`, `fail(msg)?`, `skip(reason)?` (never to hide a bug).
- Cover success, boundaries (empty, one, max) and each failure path. Name tests by behavior.
- Keep the core pure; fake capabilities with a small type. Files: `dir := temporary("p")?` from `@std/os/fs.ms`.
- A custom error enum: check `r.is_error()` and compare `r.err()`.
- Property tests: `check(name, gen, fn)` from `@std/test/property.ms` (`ints`, `lists`, `strings`, `optionals`, ...); build a fresh generator per use. Use for round trips and laws. `--runs`, `--seed`, `--fuzz 30s`.
- Shared setup: `fn make_fixture() T`, hooks `before_all/before_each/after_each/after_all`, read as `fixture`.
- Golden files: `expect_golden(path, actual)?`; `MS_UPDATE_GOLDEN=1` rewrites.

```sh
ms test ms.toml [--filter name] [--list] [--json] [--fail-fast]
```

A failure prints both values and a position. Fix the code or the expectation; never loosen or skip a test. Then run the program itself, then `ms verify --deny-warnings`.

<!-- complete-test: testing-cart.ms -->
```manuscript
import (
	check, ints, lists from "@std/test/property.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

fn shipping(subtotal: Int) Int:
	if subtotal >= 4000: return 0
	return 500

fn order_total(prices: List[Int]) Int!:
	for price in prices:
		if price < 0: return error(Error(f"negative price {price}", kind: "EINVAL"))

	subtotal := prices.sum()
	return ok(subtotal + shipping(subtotal))

test "small orders pay shipping":
	expect_equal(order_total([1250, 800])?, 2550)?

test "empty order pays shipping":
	expect_equal(order_total([])?, 500)?

test "a negative price is rejected with its value":
	cause := expect_error(order_total([100, -5]))?
	expect_equal(cause.message, "negative price -5")?

test "order of items never changes the total":
	check(
		"any order",
		lists(ints(0, 5000)),
		fn prices: expect_equal(
			order_total(prices.reversed())?,
			order_total(prices)?,
		)
	)?
```
