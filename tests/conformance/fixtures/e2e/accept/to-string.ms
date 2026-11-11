// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	Queue from "@std/collections/queue.ms",
	Decimal from "@std/math/decimal.ms",
	fail from "@std/test/test.ms",
)

type Person:
	name: String
	age: Int

enum Outcome:
	Ready(value: Person)
	Waiting

interface Named:
	fn name() String

impl Named for Person:
	fn name() String:
		return self.name.clone()

fn stringify[T](value: T) String:
	return value.to_string()

fn interpolate[T](value: T) String:
	return "{value}"

fn bound_stringify[T: Named](value: T) String:
	return value.to_string()

fn check(value: String, expected: String) Unit!:
	if value != expected: return fail(message: "expected {expected}, received {value}")

fn answer() Int:
	return 42

type Counter:
	value: Int

fn next(var state: Counter) Person:
	value := state.value
	state.value = value + 1
	return Person(name: "Ada", age: value)

test "every scalar has to_string":
	(check(value: "hello".to_string(), expected: "hello")?)
	(check(value: true.to_string(), expected: "true")?)
	(check(value: false.to_string(), expected: "false")?)
	(check(value: unit.to_string(), expected: "unit")?)
	(check(value: (42).to_string(), expected: "42")?)
	(check(value: (-7).to_string(), expected: "-7")?)
	(check(value: (1.5).to_string(), expected: "1.5")?)
	(check(value: (-0.0).to_string(), expected: "-0")?)
	(check(value: (1.0 / 0.0).to_string(), expected: "Infinity")?)
	(check(value: (0.0 / 0.0).to_string(), expected: "NaN")?)
	(check(value: (1.00d).to_string(), expected: "1")?)

test "records alternatives and collections convert":
	person := Person(name: "Ada", age: 37)
	(check(value: person.to_string(), expected: "Person(age: 37, name: Ada)")?)
	(check(value: "{person}", expected: person.to_string())?)
	(
		check(
			value: Outcome.Ready(person).to_string(),
			expected: "Outcome.Ready(Person(age: 37, name: Ada))",
		)?
	)
	(check(value: Outcome.Waiting.to_string(), expected: "Outcome.Waiting")?)

	absent: Int? := none
	present: Int? := 3
	result: Int!Error := error(Error("failed"))
	(check(value: absent.to_string(), expected: "none")?)
	(check(value: present.to_string(), expected: "some(3)")?)
	(
		check(
			value: result.to_string(),
			expected: "error(Error(details: Map(), kind: none, message: failed))",
		)?
	)
	(check(value: [1, 2, 3].to_string(), expected: "[1, 2, 3]")?)
	(check(value: [[1], [2, 3]].to_string(), expected: "[[1], [2, 3]]")?)

	empty: List[Int] := []
	(check(value: empty.to_string(), expected: "[]")?)

	var map = Map[String, Int]()
	map.add(key: "b", value: 2)
	map.add(key: "a", value: 1)
	(check(value: map.to_string(), expected: "Map(b: 2, a: 1)")?)

	set := Set[Int]([2, 1])
	(check(value: set.to_string(), expected: "Set(2, 1)")?)

	bytes := Bytes([0, 65, 255])
	(check(value: bytes.to_string(), expected: "Bytes(0, 65, 255)")?)
	(
		check(
			value: "{map}|{set}|{bytes}",
			expected: "Map(b: 2, a: 1)|Set(2, 1)|Bytes(0, 65, 255)",
		)?
	)

test "generics views bound methods functions and resources":
	person := Person(name: "Ada", age: 37)
	(check(value: stringify(person), expected: person.to_string())?)
	(check(value: interpolate(person), expected: person.to_string())?)
	(check(value: bound_stringify(person), expected: person.to_string())?)

	view: Named := person.clone()
	(check(value: view.to_string(), expected: person.to_string())?)
	(check(value: "{view}", expected: person.to_string())?)

	convert: fn() String := view.to_string
	(check(value: convert(), expected: person.to_string())?)
	(check(value: answer.to_string(), expected: "[function]")?)
	(check(value: "{answer}", expected: "[function]")?)

	queue := Queue[Int](1)
	(
		check(
			value: queue.to_string(),
			expected: "Queue(capacity: some(1), head: 0, items: [])",
		)?
	)

test "interpolation and bound conversion evaluate each receiver once":
	var state = Counter(value: 1)
	(
		check(
			value: "{next(var state)}|{next(var state)}",
			expected: "Person(age: 1, name: Ada)|Person(age: 2, name: Ada)",
		)?
	)

	convert := next(var state).to_string
	(check(value: convert(), expected: "Person(age: 3, name: Ada)")?)
	(check(value: convert(), expected: "Person(age: 3, name: Ada)")?)
	(check(value: state.value.to_string(), expected: "4")?)
