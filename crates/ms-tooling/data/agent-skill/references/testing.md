# Testing

Checking proves types, ownership and exhaustiveness. Only a test or a run proves behavior. Write tests for rules where a mistake costs something, run the program on real input, and report each separately.

## Write tests

A `test "name":` block sits in the module it tests, needs no `main`, and runs with `ms test`. Assertions return Results, so end each with `?`; a bare `expect_equal(...)` statement is a check error. Import them from `@std/test/test.ms`.

- `expect_equal(actual, expected)?` prints both values on a mismatch; compare whole strings and lists, not `contains(...)` with `true`. `expect_true`, `expect_false`, `expect_not_equal`, `expect_close(a, b, tolerance)` for floats.
- `expect_some(opt)?`, `expect_ok(result)?`, `expect_error(result)?` return the payload (`cause := expect_error(r)?`); `expect_none(opt)?`. `expect_fault(fn)` checks that a call faults.
- A test's error type is `Error`, so `f()?` works on an `Int!`. For a custom error enum, check `r.is_error()` and compare `r.err()` with `expect_equal`, or translate with `map_error`.
- `fail("why")?` fails explicitly; `skip("reason")?` skips (never to hide a platform bug).
- Test success, the boundary (empty, one, maximum) and each failure path. Name tests by the behavior: `"empty cart pays no shipping"`.
- Keep the core pure so a test needs no files. When a test must touch files use `dir := temporary("prefix")?` from `@std/os/fs.ms` and `dir.path()`. When code takes a capability (a `Prices`, `Clock`, `Logger` interface), pass a small fake type.

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

## Property tests

`check(name, generator, fn)` runs a rule on many generated inputs (100 by default) and shrinks a failure to a small counterexample with a seed. Generators: `ints(lo, hi)`, `bools()`, `floats`, `strings`, `lists(gen)`, `optionals`, `pairs`, `element_of`, `one_of`, `constant`, combined with `map`, `filter`, `flat_map`. Build a fresh generator per use (it moves). Use properties for round trips (`parse(stringify(x)) == x`), ordering and size laws, and "never faults". `--runs 1000`, `--seed N` (replay), `--fuzz 30s` tune them.

## Shared setup

`fn make_fixture() T` builds one record per file; tests read it as `fixture`. Give `T` any of `before_all`, `before_each`, `after_each`, `after_all` as `fn var T.before_each() Void!`. Build in `make_fixture`, reset in `before_each`, release in `after_all`.

## Run

```sh
ms test ms.toml                      # every test in the project
ms test file.ms --filter total       # by module::name substring
ms test ms.toml --list               # names only
ms test ms.toml --json               # failures as data: values, position, trace
ms test ms.toml --fail-fast --repeat 5 --shuffle 7
```

- A failed test prints both values and a position; fix the code or the expectation, never loosen a test to pass or skip it. A failing test in an unrelated area is a finding to report.
- Golden output: `expect_golden(path, actual)?` from `@std/test/golden.ms` compares with a file; `MS_UPDATE_GOLDEN=1 ms test ...` rewrites it, then review the diff.
- Benchmarks are `bench "name":` blocks run by `ms bench`; use `keep` from `@std/test/bench.ms` so work is not optimised away.

## Run the program too

After tests pass, run the real program on a normal input, an empty input and a bad input, and read the output. Then `ms verify --deny-warnings`. Say which of check, test, run and verify you ran.
