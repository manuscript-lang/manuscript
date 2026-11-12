// conform: tags=testing,maps,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn arity(name: String) Int:
	return {"stock": 3, "price": 3, "cancel": 2, "ship": 2, "report": 1, "stock": 9}.get(name).get(0)

fn has(k: Int) Bool:
	return {1: "a", 2: "b"}.contains(k)

fn label(k: Int) String:
	return {1: "one", 2: "two"}.get(k).get("none")

fn found(k: Int) Bool:
	return {1: "one", 2: "two"}.get(k).is_some()

fn bump(var calls: Int, k: Int) Int:
	calls += 1
	return k

fn many(k: Int) Int:
	return {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 10: 10, 11: 11, 12: 12, 13: 13}.get(k).get(0)

test "a literal map answers lookups by key, the last duplicate wins":
	expect_equal(arity("stock"), 9)?
	expect_equal(arity("ship"), 2)?
	expect_equal(arity("unknown"), 0)?
	expect_equal(has(1), true)?
	expect_equal(has(3), false)?
	expect_equal(label(2), "two")?
	expect_equal(label(7), "none")?
	expect_equal(found(1), true)?
	expect_equal(found(5), false)?
	expect_equal(many(13), 13)?
	expect_equal(many(14), 0)?

test "a literal map lookup evaluates its key once":
	var calls = 0
	expect_equal({1: 10, 2: 20}.get(bump(var calls, 2)).get(0), 20)?
	expect_equal({1: 10, 2: 20}.contains(bump(var calls, 5)), false)?
	expect_equal(calls, 2)?

test "literal map values keep their type":
	expect_equal({1: 1.5, 2: 2.5}.get(2).get(0.0), 2.5)?
	expect_equal({1: true}.get(1).is_some(), true)?
	expect_equal({1: true}.get(4).is_none(), true)?
