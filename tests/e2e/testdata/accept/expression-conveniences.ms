import (
	Closeable from "@std/core.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_false, expect_ok, expect_true from "@std/test/test.ms",
)

type Counter:
	count: Int

type Resource:
	marker: String

// Cleanup runs on the resource's own copy, so a marker file is how a caller observes it.
fn var Resource.close() Unit!:
	_written := write_file(self.marker, "closed", true).wait()

fn closed(marker: String) Bool: read_file(marker).wait().is_ok()

fn identity[T](value: T) T: return value

fn amount(text: String, marker: String) Int!Error:
	_resource := Resource(marker: marker.clone())

	cents := match text.parse_int():
		value:
			value
		none:
			return error(cause: Error("Invalid amount"))

	return ok(value: cents + 1)

fn early(value: Int?) Int:
	number := match value:
		number: number
		none: return 9

	return number + 1

fn all_return(value: Int?) Int:
	_unreachable := match value:
		number: return number
		none: return 9

fn tick(var counter: Counter) Int!:
	counter.count | expect_equal(1)?
	counter.count += 1
	return ok(0)

fn values(var counter: Counter) List[Int]:
	counter.count += 1
	return [7, 8]

test "indexing and generic applications coexist":
	items := [10, 20]
	index := 1
	indices := [0, 1]
	var counter = Counter(count: 0)
	((items[0] != 10 or items[index] != 20 or items[-1] != 20)) | expect_false?
	(items[indices[index]] != 20 or items[index - 1] != 10) | expect_false?
	(items[counter.count] != 10 or [items.clone()][0][1] != 20) | expect_false?
	(values(var counter)[(tick(var counter)?)] != 7 or counter.count != 2) | expect_false?
	identity[Int](items[0]) | expect_equal(10)?

	callbacks: List[fn(Int) Int] := [identity[Int]]
	(callbacks[0](2) != 2 or callbacks[indices[0]](3) != 3) | expect_false?

test "empty list constructors have fresh typed storage":
	var empty = List[String]()
	contextual: List[Int] := List()
	other := List[String]()
	empty.append("a")
	(empty[0] != "a" or not other.is_empty() or not contextual.is_empty()) | expect_false?

	map := Map[String, Int]()
	map.length() | expect_equal(0)?

test "string concatenation and scalar ordering":
	lines := ["a", "b"]
	(lines.join("\n") + "\n") | expect_equal("a\nb\n")?
	(("" < "a" and "a" < "aa" and "é" > "z" and "a" <= "a" and "a" >= "a")) | expect_true?
	("a" < "a" or "a" > "a" or "b" <= "a" or "a" >= "b") | expect_false?
	("" + "value" != "value" or "value" + "" != "value") | expect_false?
	("\u{e000}" < "\u{10000}") | expect_true?

	sorted := ["z", "a", "b"].sorted(
		fn(left: String, right: String) Int:
			if left < right: return -1
			if left > right: return 1

			return 0
	)

	sorted | expect_equal(["a", "b", "z"])?

test "match expressions preserve returns and cleanup":
	present: Int? := 4
	absent: Int? := none
	(early(present) != 5 or early(absent) != 9 or all_return(present) != 4) | expect_false?

	var temporary = temporary("manuscript-match-") | expect_ok?
	dir := temporary.path()
	parsed := amount(text: "3", marker: "{dir}/parsed")
	(parsed != Result[Int, Error].ok(value: 4)) | expect_false?
	closed("{dir}/parsed") | expect_true?

	invalid := amount(text: "invalid", marker: "{dir}/invalid")
	(invalid != Result[Int, Error].error(cause: Error("Invalid amount"))) | expect_false?
	closed("{dir}/invalid") | expect_true?
	temporary.close()?

	nested := match present:
		value:
			// manuscript:allow-nested-match regression for nested expression values and the absent branch
			match absent:
				other: value + other
				none: value
		none: 0

	nested | expect_equal(4)?

	contextual: List[Int] := match absent:
		value: [value]
		none: []

	contextual.length() | expect_equal(0)?

	result := identity[Int](
		match present:
			value: value
			none: 0
	)
	result | expect_equal(4)?

	callback := fn(value: Int?) Int:
		number := match value:
			number: number
			none: return 42

		return number

	callback(absent) | expect_equal(42)?

test "indexes read elements and get supplies defaults":
	values := [1, 2]
	values.get(2, default: 0) | expect_equal(0)?
	values.get(-3, default: 0) | expect_equal(0)?
	values.get(-9223372036854775808, default: 0) | expect_equal(0)?
	(values[0] != values.get(0) or values[-1] != values.get(-1)) | expect_false?
	List[Int]().get(0, default: 7) | expect_equal(7)?

test "match blocks produce their final value":
	present: Int? := 5

	result := match present:
		value:
			doubled := value * 2
			doubled + 1
		none: 0

	result | expect_equal(11)?

	var count = 0

	while true:
		count += 1

		match present:
			value:
				if count < value: continue

				break
			none: break

	count | expect_equal(5)?

test "contextual values infer from later arms":
	present: Int? := 5

	optional: Int? := match present:
		none: none
		value: value

	optional.get() | expect_equal(5)?

	list := match present:
		none: []
		value: [value]

	list[0] | expect_equal(5)?

fn returned_argument(var counter: Counter) Int!:
	absent: Int? := none
	return ok(
		combine(
			first: match absent:
				value: value
				none: return ok(17)
			,
			second: (tick(var counter)?)
		)
	)

fn combine(first: Int, second: Int) Int: return first + second

fn propagated(text: String) Int!Error:
	result := match text.parse_int():
		value:
			Result[Int, Error].ok(value: value)?
		none:
			Result[Int, Error].error(cause: Error("missing"))?

	return ok(value: result)

fn returned_loop(value: Int?) Int:
	var index = 0

	while true:
		if index > 1: return 23

		match value:
			_number:
				index += 1
				continue
			none: break

	return 24

test "expression exits preserve caller boundaries and evaluation order":
	var counter = Counter(count: 0)
	((returned_argument(var counter)?) != 17 or counter.count != 0) | expect_false?
	propagated("3") | expect_equal(Result[Int, Error].ok(value: 3))?
	propagated("no") | expect_equal(Result[Int, Error].error(cause: Error("missing")))?

	present: Int? := 1
	absent: Int? := none
	(returned_loop(present) != 23 or returned_loop(absent) != 24) | expect_false?

	var iterations = 0

	while true:
		value := match present:
			number:
				while iterations < 3:
					iterations += 1
					if iterations == 2: continue
					if iterations == 3: break
				number
			none: break

		if value == 1: break

	iterations | expect_equal(3)?

fn condition_exit(value: Int?) Int:
	while true:
		while (
			match value:
				_number: true
				none: break
		):
			return 1

	return 2

test "match in a loop header exits its lexical enclosing loop":
	absent: Int? := none
	condition_exit(absent) | expect_equal(2)?

test "indexing preserves zero and nested optionals":
	numbers := [0]
	(numbers[0] != 0 or numbers.get(0, default: 99) != 0) | expect_false?

	nested: List[Int?] := [none, 0]
	(nested[0].is_some() or nested[1].get() != 0) | expect_false?

fn observed_optional(var counter: Counter) Int?:
	counter.count += 1
	return 5

test "match evaluates its input once and only the selected arm":
	var counter = Counter(count: 0)

	result := match observed_optional(var counter):
		value:
			counter.count += 10
			value + 1
		none:
			counter.count += 100
			0

	(result != 6 or counter.count != 11) | expect_false?

fn inline_match(value: Int?) Int: match value:
	number: number
	none: 0

test "match composes with inferred callbacks and map literals":
	values: List[Int?] := [3, none]
	mapped := values.map(
		fn value: match value:
			number: number + 1
			none: 0
	)
	(mapped[0] != 4 or mapped[1] != 0) | expect_false?

	lookup := {
		"value": match values[0]:
			number: number
			none: 0
	}
	lookup["value"] | expect_equal(3)?
	(inline_match(none) != 0 or inline_match(5) != 5) | expect_false?
