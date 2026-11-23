// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	JsonOptions from "@std/data/json.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

type Counter:
	calls: Int

fn fallback(var counter: Counter) Int:
	counter.calls += 1
	return 42

fn value_or[T](fallback: T, value: T?) T:
	inner := value
	if inner != null: return inner

	return fallback

fn increment(value: Int) Int: value + 1

test "Optional presence and extraction preserve false and zero":
	present: Int? := 0
	missing: Int? := null
	expect_false(not (present != null))?
	expect_false(present == null)?
	expect_false(missing != null)?
	expect_false(not (missing == null))?
	expect_equal(present or panic("called Optional.get() on null"), 0)?

	flag: Bool? := false
	expect_false(flag or panic("called Optional.get() on null"))?
	expect_equal(value_or(7, missing), 7)?
	expect_equal(value_or(7, present), 0)?
	expect_false(missing != null)?

test "the fallback of or runs only when the value is null":
	present: Int? := 0
	missing: Int? := null
	var counter = Counter(0)
	expect_equal(present or fallback(counter), 0)?
	expect_equal(counter.calls, 0)?
	expect_equal(missing or fallback(counter), 42)?
	expect_equal(counter.calls, 1)?

	create := fn() Int?: 42
	expect_equal((present or create()) or panic("called Optional.get() on null"), 0)?
	expect_equal((missing or create()) or panic("called Optional.get() on null"), 42)?

test "Optional methods retain generic payload and receiver identity":
	inner: Int? := null
	outer: Int?? := inner
	expect_true(outer == null)?  // `Int??` is `Int?`: a nullable of a nullable has no second layer

	counter := Counter(3)
	record: Counter? := counter.clone()
	expect_equal((record or panic("called Optional.get() on null")).calls, 3)?

	callback: (fn(Int) Int)? := increment
	expect_equal((callback or panic("called Optional.get() on null"))(2), 3)?

	snapshot := outer.clone()
	expect_equal(snapshot, outer)?

test "Optional fallbacks preserve standard option records":
	limits := JsonOptions(max_bytes: -1)
	missing: JsonOptions? := null
	var extracted = (missing or limits).clone()
	expect_equal(extracted.max_bytes or panic("called Optional.get() on null"), -1)?
	expect_false(not (extracted.max_depth == null))?
	extracted.max_values = 7
	expect_equal(extracted.max_values or panic("called Optional.get() on null"), 7)?

test "Optional methods work on inferred library return values":
	values := [1, 2]
	expect_equal(values.get(0), 1)?
	expect_equal(values.get_or(5, 9), 9)?
