// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	JsonOptions from "@std/data/json.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

type Counter:
	calls: Int

fn fallback(var counter: Counter) Int:
	counter.calls += 1
	return 42

fn value_or[T](value: T?, fallback: T) T:
	if inner := value: return inner
	return fallback

fn increment(value: Int) Int: value + 1

test "Optional presence and extraction preserve false and zero":
	present: Int? := 0
	missing: Int? := none
	expect_false(not (present.is_some()))?
	expect_false(present.is_none())?
	expect_false(missing.is_some())?
	expect_false(not (missing.is_none()))?
	expect_equal(present.get(), 0)?

	flag: Bool? := false
	expect_false(flag.get())?
	expect_equal(value_or(missing, 7), 7)?
	expect_equal(value_or(present, 7), 0)?
	expect_false(missing.is_some())?

test "Optional fallbacks distinguish eager and lazy evaluation":
	present: Int? := 0
	missing: Int? := none
	var counter = Counter(0)
	expect_equal(present.get(fallback(var counter)), 0)?
	expect_equal(counter.calls, 1)?

	create := fn() Int?: 42
	expect_equal(present.or_else(create).get(), 0)?
	expect_equal(missing.or_else(create).get(), 42)?

test "Optional methods retain generic payload and receiver identity":
	inner: Int? := none
	outer: Int?? := inner
	expect_false(not (outer.is_some()))?
	expect_false(not (outer.get().is_none()))?

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
	missing: JsonOptions? := none
	var extracted = missing.get(limits).clone()
	expect_equal(extracted.max_bytes.get(), -1)?
	expect_false(not (extracted.max_depth.is_none()))?
	extracted.max_values = 7
	expect_equal(extracted.max_values.get(), 7)?

test "Optional methods work on inferred library return values":
	values := [1, 2]
	expect_equal(values.get(0), 1)?
	expect_equal(values.get(5, default: 9), 9)?
