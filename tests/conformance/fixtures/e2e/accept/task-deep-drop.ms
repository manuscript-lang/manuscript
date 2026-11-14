// conform: tags=testing,tier-io
// conform: phase=test
import (
	Placement, PromiseOptions, promise from "@std/concurrency/promise.ms",
	expect_equal from "@std/test/test.ms",
)
import parse from "@std/data/toml.ms"

// A task runs on a 512 KiB stack slot, so freeing data that nests thousands of levels
// deep must not recurse once per level.
fn nested_tables(n: Int) String!:
	return ok("a = " + "\{ a = ".repeat(n)? + "1" + " \}".repeat(n)? + "\n")

fn nested_arrays(n: Int) String!:
	return ok("a = " + "[".repeat(n)? + "]".repeat(n)? + "\n")

fn parse_and_drop(text: String) Int:
	value := parse(text)
	if value.is_error(): return -1
	return 1

test "a deep inline table is freed in a promise that starts here":
	text := nested_tables(6000)?
	p := promise(
		fn: ok(parse_and_drop(text)),
		options: PromiseOptions(placement: Placement.Here)
	)
	expect_equal(p.wait().get(0), 1)?

test "a deep inline table is freed in a promise that spreads":
	text := nested_tables(6000)?
	p := promise(
		fn: ok(parse_and_drop(text)),
		options: PromiseOptions(placement: Placement.Spread)
	)
	expect_equal(p.wait().get(0), 1)?

test "nested arrays are freed in a promise":
	text := nested_arrays(9000)?
	p := promise(
		fn: ok(parse_and_drop(text)),
		options: PromiseOptions(placement: Placement.Here)
	)
	expect_equal(p.wait().get(0), 1)?

test "deep data is freed on the main task":
	text := nested_tables(6000)?
	expect_equal(parse_and_drop(text), 1)?
