import expect_contains, expect_equal, expect_fault from "@std/test/test.ms"

fn replace_text(var key: String) Int:
	key = "long-dynamic-map-key-2"
	return 5

fn replace_number(var key: Int) Int:
	key = 2
	return 5

test "a counter retains its explicitly cloned mutable key":
	var values = {"long-dynamic-map-key-1": 1, "long-dynamic-map-key-2": 20}
	var key = "long-dynamic-map-key-{1}"
	values.add(key.clone(), values.get_or(key, 0) + replace_text(var key))
	expect_equal(values["long-dynamic-map-key-1"], 6)?
	expect_equal(values["long-dynamic-map-key-2"], 20)?

test "a commuted counter lookup can select a new mutable key":
	var values = {1: 1, 2: 20}
	var key = 1
	values.add(key, replace_number(var key) + values.get_or(key, 0))
	expect_equal(values[1], 25)?
	expect_equal(values[2], 20)?

test "a counter reads its old scalar key before the next operand":
	var values = {1: 1, 2: 20}
	var key = 1
	values.add(key, values.get_or(key, 0) + replace_number(var key))
	expect_equal(values[1], 6)?
	expect_equal(values[2], 20)?

test "immutable dynamic keys keep counter arithmetic":
	key := "long-dynamic-map-key-{1}"
	var values: Map[String, Int] = Map()
	values.add(key.clone(), values.get_or(key, 3) + 2)
	values.add(key.clone(), values.get_or(key, 0) * 4)
	values.add(key.clone(), values.get_or(key, 0) - 1)
	expect_equal(values[key], 19)?

test "immutable scalar and literal keys keep counter updates":
	key := 1
	var values: Map[Int, Int] = Map()
	values.add(key, 2 + values.get_or(key, 3))
	values.add(2, values.get_or(2, 4) * 3)
	expect_equal(values[1], 5)?
	expect_equal(values[2], 12)?

test "stable counter updates keep checked integer overflow":
	key := 1
	var values = {1: 9223372036854775807}
	message := expect_fault(fn: values.add(key, values.get_or(key, 0) + 1))?
	expect_contains(message, "overflow")?

test "counter keys apply their checked Optional conversion":
	var values = Map[Int?, Int]()
	values.add(1, values.get_or(1, 0) + 1)
	values.add(2, values.get_or(2, 3) * 2)
	expect_equal(values.get_or(1, 0), 1)?
	expect_equal(values.get_or(2, 0), 6)?
	expect_equal(values.length(), 2)?

test "already Optional counter keys retain their representation":
	key: Int? := 1
	var values = Map[Int?, Int]()
	values.add(key, values.get_or(key, 0) + 2)
	expect_equal(values.get_or(1, 0), 2)?
	expect_equal(values.length(), 1)?

fn consume_text(key: String) Int:
	values := [key]
	return values.length() + 4

test "an immutable counter key can be consumed after its lookup":
	var values = {"long-dynamic-map-key-1": 1}
	key := "long-dynamic-map-key-{1}"
	values.add(key.clone(), values.get_or(key, 0) + consume_text(key))
	expect_equal(values["long-dynamic-map-key-1"], 6)?

test "a map add retains its cloned key while its source is consumed":
	var values: Map[String, Int] = Map()
	key := "long-dynamic-map-key-{1}"
	values.add(key.clone(), consume_text(key))
	expect_equal(values["long-dynamic-map-key-1"], 5)?

test "a map add default retains its key while its source is consumed":
	var values: Map[String, Int] = Map()
	key := "long-dynamic-map-key-{1}"
	values.add_default(key.clone(), consume_text(key))
	expect_equal(values["long-dynamic-map-key-1"], 5)?

fn consume_keys(keys: List[String]) Int:
	nested := [keys]
	return nested.length() + 4

test "an indexed key clone survives consuming its container":
	var values: Map[String, Int] = Map()
	keys := ["long-dynamic-map-key-{1}"]
	values.add(keys[0].clone(), consume_keys(keys))
	expect_equal(values["long-dynamic-map-key-1"], 5)?

test "literal increments keep stable mutable-key counters":
	var key = "long-dynamic-map-key-{1}"
	var values: Map[String, Int] = Map()
	values.add(key.clone(), values.get_or(key, 0) + 1)
	key = "long-dynamic-map-key-{2}"
	values.add(key.clone(), values.get_or(key, 0) + 1)
	expect_equal(values["long-dynamic-map-key-1"], 1)?
	expect_equal(values["long-dynamic-map-key-2"], 1)?

// Source methods named clone must run even when the arithmetic fits counter fusion.
type CounterKey:
	value: Int

impl CounterKey:
	fn clone() CounterKey:
		return CounterKey(self.value + 1)

test "counter updates call a source-defined clone method":
	key := CounterKey(1)
	var values = {CounterKey(1): 1}
	values.add(key.clone(), values.get_or(key, 0) + 1)
	expect_equal(values[CounterKey(1)], 1)?
	expect_equal(values[CounterKey(2)], 2)?

fn successful_value(value: Int) Int!:
	return ok(value)

fn failed_value() Int!:
	return error(Error("expected map value failure"))

fn add_failed_value(var values: Map[String, Int], key: String) Unit!:
	values.add(key.clone(), failed_value()?)

test "an owned native argument transfers after a later try succeeds":
	key := "long-dynamic-map-key-{1}"
	var values: Map[String, Int] = Map()

	// Referencing the owner prevents borrowed-key elision, as in TOML materialization.
	values.add(key.clone(), successful_value(key.length())?)
	values.add_default(key.clone(), successful_value(key.length() + 1)?)
	expect_equal(values[key], key.length())?

test "a moved native argument survives a later try without rereading its source":
	key := "long-dynamic-map-key-{1}"
	var values: Map[String, Int] = Map()
	values.add(key, successful_value(7)?)
	expect_equal(values["long-dynamic-map-key-1"], 7)?

test "a later failing try leaves its map unchanged":
	var values: Map[String, Int] = Map()
	result := add_failed_value(var values, "long-dynamic-map-key-{1}")
	expect_equal(result.is_error(), true)?
	expect_equal(values.length(), 0)?

type FaultingCounterKey:
	value: Int

impl FaultingCounterKey:
	fn clone() FaultingCounterKey:
		checked := self.value + 1
		return FaultingCounterKey(checked - 1)

test "counter fusion preserves faults from an equal-valued source clone":
	key := FaultingCounterKey(9223372036854775807)
	var values = {FaultingCounterKey(9223372036854775807): 1}
	message := expect_fault(fn: values.add(key.clone(), values.get_or(key, 0) + 1))?
	expect_contains(message, "overflow")?

test "native borrowers retain owned arguments after a later try":
	separator := "long-dynamic-map-key-{1}"
	pieces := "before-long-dynamic-map-key-1-after".split(
		separator.clone(), max_parts: successful_value(2)?
	)
	expect_equal(pieces, ["before-", "-after"])?
