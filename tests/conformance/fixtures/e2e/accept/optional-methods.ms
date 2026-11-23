// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	JsonOptions from "@std/data/json.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

type Counter:
	calls: Int

fn fallback(var counter: Counter) Int:
	counter.calls += 1
	return 42

fn value_or[T](fallback: T, value: T?) T:
	if inner := value: return inner
	return fallback

fn increment(value: Int) Int: value + 1

test "Optional presence and extraction preserve false and zero":
	present: Int? := 0
	missing: Int? := null
	expect_false(not (present.is_some()))?
	expect_false(present.is_none())?
	expect_false(missing.is_some())?
	expect_false(not (missing.is_none()))?
	expect_equal(present.get(), 0)?

	flag: Bool? := false
	expect_false(flag.get())?
	expect_equal(value_or(7, missing), 7)?
	expect_equal(value_or(7, present), 0)?
	expect_false(missing.is_some())?

test "Optional fallbacks distinguish eager and lazy evaluation":
	present: Int? := 0
	missing: Int? := null
	var counter = Counter(0)
	expect_equal(present.get_or(fallback(counter)), 0)?
	expect_equal(counter.calls, 1)?

	create := fn() Int?: 42
	expect_equal(present.or_else(create).get(), 0)?
	expect_equal(missing.or_else(create).get(), 42)?

test "Optional methods retain generic payload and receiver identity":
	inner: Int? := null
	outer: Int?? := inner
	expect_true(outer.is_none())? // `Int??` is `Int?`: a nullable of a nullable has no second layer

	counter := Counter(3)
	record: Counter? := counter.clone()
	expect_equal(record.get().calls, 3)?

	extract := record.get
	expect_equal(extract().calls, 3)?

	callback: (fn(Int) Int)? := increment
	expect_equal(callback.get()(2), 3)?

	snapshot := outer.clone()
	expect_equal(snapshot, outer)?

test "Optional fallbacks preserve standard option records":
	limits := JsonOptions(max_bytes: -1)
	missing: JsonOptions? := null
	var extracted = missing.get_or(limits).clone()
	expect_equal(extracted.max_bytes.get(), -1)?
	expect_false(not (extracted.max_depth.is_none()))?
	extracted.max_values = 7
	expect_equal(extracted.max_values.get(), 7)?

test "Optional methods work on inferred library return values":
	values := [1, 2]
	expect_equal(values.get(0), 1)?
	expect_equal(values.get_or(5, 9), 9)?
