// conform: tags=testing,tier-io
// conform: phase=test
import (
	Placement, PromiseOptions, promise from "@std/concurrency/promise.ms",
	parse from "@std/data/semver.ms",
	expect_equal from "@std/test/test.ms",
)

// The pieces of `split` borrow the text they came from. A copy of a piece taken inside
// a
// `for` loop must stay a copy even though the loop drops the piece right after, because the
// source is freed when the function returns.
fn identifiers(version: String) List[String]:
	parts := [version.take(6), version.drop(6)]
	var found = List[String]()
	for identifier in parts[1].split("."):
		found.append(identifier.clone())
	return found

fn churn() Int:
	var total = 0
	for i in 0..20:
		total += "scratch-{i}-allocation-that-reuses-freed-blocks".length()
	return total

fn check(rounds: Int) Int!:
	var bad = 0

	for i in 0..rounds:
		found := identifiers("1.0.0-99999999999999999999.100000000000000000000")
		_ := churn()
		if (
			found.length() != 2
			or found[0] != "99999999999999999999"
			or found[1] != "100000000000000000000"
		):
			bad += 1

		small := parse(text: "1.0.0-99999999999999999999")?
		large := parse(text: "1.0.0-100000000000000000000")?
		if small.prerelease != ["99999999999999999999"] or small.compare(large) != -1: bad += 1

	return ok(bad)

fn spread(lo: Int, hi: Int) Int!:
	if hi - lo == 1: return check(50)

	mid := (lo + hi) / 2
	upper := promise(
		fn: spread(mid, hi),
		options: PromiseOptions(placement: Placement.Spread)
	)
	low := spread(lo, mid)?
	return ok(low + upper.wait()?)

test "a copied split piece outlives its source":
	expect_equal(check(50)?, 0)?

test "a copied split piece outlives its source on worker threads":
	expect_equal(spread(0, 16)?, 0)?
