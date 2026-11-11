import (
	panic from "@std/core.ms",
	JsonOptions from "@std/data/json.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

type Counter:
	calls: Int

type Pending:
	values: List[Int]

fn bump(var counter: Counter) Int:
	counter.calls += 1
	return 9

fn map_result[T, E, U](value: T!E, transform: fn(T) U) U!E:
	return value.map(transform)

fn chain_result[T, E, U](value: T!E, transform: fn(T) U!E) U!E:
	return value.and_then(transform)

fn map_optional[T, U](value: T?, transform: fn(T) U) U?:
	return value.map(transform)

fn map_set[T: Hashable, U: Hashable](values: Set[T], transform: fn(T) U) Set[U]:
	return values.map[U](transform)

test "core parity operations are callable":
	success: Int!Error := ok(2)
	failure: Int!Error := error(Error("failed"))
	try expect_false(not (success.is_ok()) or success.is_error())
	try expect_false(success.get() != 2 or failure.err().message != "failed")
	try expect_equal(failure.get(7), 7)
	try expect_equal(failure.get_or_else(fn cause: cause.message.scalar_length()), 6)
	try expect_equal(success.map(fn n: n + 1).get(), 3)

	chained: String!Error := success.and_then(fn n: ok(n.to_string()))
	try expect_equal(chained.get(), "2")

	present: Int? := 2
	missing: Int? := none
	try expect_equal(present.map(fn n: n + 1).get(), 3)
	try expect_equal(present.and_then(fn(n: Int) String?: n.to_string()).get(), "2")
	try expect_equal(missing.or_else(fn: 4).get(), 4)

	values: Map[String, Int] := {"a": 1, "b": 2}
	try expect_false(values.is_empty() or values.get_or("absent", 8) != 8)
	try expect_equal(values.filter(fn k, v: k == "b" and v == 2).length(), 1)

	members := Set[Int]([2, 3])
	try expect_false(members.is_empty() or members.filter(fn n: n == 2).length() != 1)
	try expect_equal(members.map(fn n: n.to_string()).values(), ["2", "3"])

fn unexpected_text(value: Int) String:
	return panic("transform must not run for errors")

fn unexpected_chain(value: Int) String!Counter:
	return panic("chain must not run for errors")

test "Result preserves unconstrained payloads and success-only composition":
	counter := Counter(0)
	failure: Int!Counter := error(counter.clone())
	success: Int!Counter := ok(0)
	skipped := map_result(failure.clone(), unexpected_text)
	try expect_false(not (skipped.is_error()) or skipped.is_ok())

	var skipped_cause = skipped.err().clone()
	skipped_cause.calls = 2
	try expect_equal(counter.calls, 0)
	try expect_equal(skipped.err().calls, 0)

	mapped := success.clone().map(fn value: value.to_string())
	try expect_equal(mapped.get(), "0")

	propagated := chain_result(failure.clone(), unexpected_chain)
	try expect_false(not (propagated.is_error()))

	var propagated_cause = propagated.err().clone()
	propagated_cause.calls = 4
	try expect_equal(counter.calls, 0)

	produced := (
		success
		.clone()
		.and_then(fn value: Result[String, Counter].error(counter.clone()))
	)
	try expect_false(not (produced.is_error()))

	var produced_cause = produced.err().clone()
	produced_cause.calls = 6
	try expect_equal(counter.calls, 0)
	try expect_equal(produced.err().calls, 0)

	collection_error: Bool!Pending := error(Pending([1]))
	var pending = Pending(
		collection_error.clone().map(fn flag: not flag).err().values.clone()
	)
	pending.values.append(2)
	try expect_equal(pending.values, [1, 2])
	try expect_equal(collection_error.err().values, [1])

	limits := JsonOptions(max_bytes: -1)
	record: JsonOptions!Error := ok(limits.clone())
	var changed = record.clone().map(fn value: value).get().clone()
	changed.max_values = 7
	try expect_equal(changed.max_values.get(), 7)
	try expect_false(limits.max_values.is_some())

	nested := success.clone().map(fn(n: Int) Int?: n)
	try expect_equal(nested.get().get(), 0)

	unit_result: Unit!Error := ok(unit)
	try expect_false(not (unit_result.is_ok()))

	bool_result: Bool!Error := ok(false)
	try expect_false(bool_result.get(true))

test "Result fallbacks are eager or lazy and bound methods keep receivers":
	var counter = Counter(0)
	success: Int!Counter := ok(0)
	failure: Int!Counter := error(counter.clone())
	try expect_false(success.get(bump(var counter)) != 0 or counter.calls != 1)

	create := fn(cause: Counter) Int: 12
	unexpected := fn(cause: Counter) Int: panic("fallback must stay lazy")
	lazy := success.clone().get_or_else
	try expect_false(lazy(unexpected) != 0)
	try expect_false(failure.clone().get_or_else(create) != 12)

	extract := failure.clone().err
	var extracted = extract().clone()
	extracted.calls = 3
	try expect_equal(failure.err().calls, 0)
	try expect_equal(extracted.calls, 3)

	bound_map := success.clone().map[String]
	bound_chain := success.clone().and_then[String]
	try expect_equal(bound_map(fn n: n.to_string()).get(), "0")
	try expect_equal(bound_chain(fn n: ok(n.to_string())).get(), "0")

test "Optional composition keeps nesting identity and lazy callback counts":
	counter := Counter(0)
	present: Counter? := counter.clone()
	missing: Counter? := none
	transform := fn(value: Counter) Counter:
		return Counter(value.calls + 1)
	unexpected := fn(value: Counter) Counter: panic("map must not run for none")
	try expect_false(not (map_optional(missing.clone(), unexpected).is_none()))

	mapped := present.clone().map(transform)
	try expect_equal(mapped.get().calls, 1)
	try expect_equal(counter.calls, 0)

	var edited = mapped.get().clone()
	edited.calls = 2
	try expect_equal(mapped.get().calls, 1)

	chained := present.clone().and_then(fn(value: Counter) Counter?: value)
	try expect_equal(chained.get().calls, 0)

	absent := present.clone().and_then(fn(unused: Counter) Int?: none)
	try expect_false(not (absent.is_none()))

	create := fn() Counter?: Counter(5)
	unexpected_create := fn() Counter?: panic("fallback must stay lazy")
	bound := present.clone().or_else
	try expect_equal(bound(unexpected_create).get().calls, 0)

	fallback := missing.clone().or_else(create)
	try expect_equal(fallback.get().calls, 5)

	nested := present.clone().map(fn(unused: Counter) Int?: none)
	try expect_false(not (nested.is_some()) or not (nested.get().is_none()))

	bound_map := mapped.clone().map[String]
	try expect_equal(bound_map(fn value: value.calls.to_string()).get(), "1")

	bound_chain := missing.clone().and_then[String]
	try expect_false(not (bound_chain(fn unused: "unexpected").is_none()))

test "Map filter copies ordered membership and get_or never inserts":
	var counter = Counter(0)
	values: Map[String, Counter] := {
		"b": counter.clone(),
		"a": Counter(2),
		"c": Counter(3)
	}
	var selected = values.clone().filter(fn k, v: k != "a" and v.calls >= 0)
	try expect_false(selected.keys() != ["b", "c"] or values.length() != 3)

	var changed = selected.get_or("b", Counter(9)).clone()
	changed.calls = 7
	try expect_equal(values.get_or("b", Counter(9)).calls, 0)
	selected.remove("b")
	selected.add("d", Counter(4))
	try expect_equal(values.keys(), ["b", "a", "c"])

	fallback := Counter(8)
	lookup := values.clone().get_or
	var fallback_copy = lookup(fallback: fallback.clone(), "absent").clone()
	fallback_copy.calls = 9
	try expect_false(fallback.calls != 8 or values.contains("absent"))
	try expect_false(
		(
			Map[String, Int]().get_or("absent", bump(var counter)) != 9
			or counter.calls != 1
		)
	)

	var empty = values.clone().filter(fn unused_key, unused_value: false)
	try expect_false(not (empty.is_empty()))
	empty.add("new", counter.clone())
	try expect_false(values.contains("new"))

	bound_filter := values.clone().filter
	try expect_equal(bound_filter(fn k, v: k == "a").keys(), ["a"])

	snapshot: Map[String, Int] := {"b": 2, "a": 1, "c": 3}
	copied := snapshot.clone().filter(fn k, v: v != 1)
	try expect_false(copied.keys() != ["b", "c"] or copied.values() != [2, 3])
	try expect_equal(snapshot.keys(), ["b", "a", "c"])

type Key:
	id: Int
	label: String

impl Equal for Key:
	fn equals(other: Key) Bool:
		return self.id == other.id

impl Hashable for Key:
	fn hash() Int: 0

test "Set filter and map copy snapshots and deduplicate in first-result order":
	values := Set[Int]([3, 1, 2])
	var copied = values.clone().filter(fn n: n != 1)
	try expect_false(copied.values() != [3, 2])
	copied.remove(3)
	copied.add(8)
	try expect_equal(values.values(), [3, 1, 2])

	bound_filter := copied.clone().filter
	try expect_equal(bound_filter(fn n: n == 8).values(), [8])

	input := Set[Int]([2, 3, 4])
	mapped := map_set(input.clone(), fn n: Key(n % 2, n.to_string()))
	try expect_false(
		(
			mapped.length() != 2
			or mapped.values().get(0).label != "2"
			or mapped.values().get(1).label != "3"
		)
	)

	bound := input.clone().map[String]
	var mapped_snapshot = bound(fn n: n.to_string())
	try expect_false(mapped_snapshot.values() != ["2", "3", "4"])
	mapped_snapshot.add("8")
	try expect_equal(input.length(), 3)

	key := Key(5, "shared")
	keys := Set[Key]([key.clone()])
	var first = keys.clone().filter(fn unused: true).values().get(0).clone()
	first.label = "changed"

	var second = keys.clone().map(fn value: value.clone()).values().get(0).clone()
	second.label = "again"
	try expect_equal(key.label, "shared")
	try expect_equal(keys.values().get(0).label, "shared")
	try expect_false(not (Set[Int]().map(fn n: n.to_string()).is_empty()))
	try expect_false(not (keys.filter(fn unused: false).is_empty()))
