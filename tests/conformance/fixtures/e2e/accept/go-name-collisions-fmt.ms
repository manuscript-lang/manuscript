// conform: tags=alternatives,control-flow,formatter,generics,interfaces,interpolation,match,modules,parser,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/go-name-collisions.ms
import expect_equal, expect_false from "@std/test/test.ms"

type Spelled:
	x_: Int
	x: Int
	a_b: Int
	aB: Int

interface Methods:
	fn foo_bar() Int
	fn fooBar() Int

impl Methods for Spelled:
	fn foo_bar() Int:
		return self.x_

	fn fooBar() Int:
		return self.x

fn string(value: Int) Int:
	return value + 1

fn int(value: Int) Int:
	return value + 2

fn float64(value: Int) Int:
	return value + 3

fn nil(value: Int) Int:
	return value + 4

test "field names that differ only in underscores stay distinct":
	value := Spelled(1, 2, 3, 4)
	expect_false(value.x_ != 1 or value.x != 2 or value.a_b != 3 or value.aB != 4)?

	var clone = value.clone()
	clone.x_ = 9
	expect_false(value.x_ != 1 or clone.x_ != 9)?
	expect_equal(value, Spelled(1, 2, 3, 4))?

test "operation names that differ only in underscores stay distinct":
	methods: Methods := Spelled(1, 2, 3, 4)
	expect_false(methods.foo_bar() != 1 or methods.fooBar() != 2)?

test "functions named like Go predeclared identifiers still lower":
	text := "{string(1)}{int(1)}{float64(1)}{nil(1)}"
	floats := [1.5, 2.5]
	expect_false(text != "2345" or floats.length() != 2)?

type Box[T]:
	value: T

type Box_Int:
	value: String

enum Shape:
	Circle(radius: Int)
	Square(side: Int)

type Shape_Circle:
	radius: String

fn side(shape: Shape) Int:
	match shape:
		Circle(radius): return radius
		Square(side): return side

test "declared names stay apart from instantiation and case names":
	boxed := Box[Int](1)
	named := Box_Int("one")
	expect_false(boxed.value != 1 or named.value != "one")?
	expect_false(side(Shape.Circle(3)) != 3 or side(Shape.Square(4)) != 4)?
	expect_equal(Shape_Circle("r").radius, "r")?

interface Counter:
	fn count() Int

type Tally:
	total: Int

impl Counter for Tally:
	fn count() Int:
		return self.total

type Counter_Tally:
	other: Int

fn clone_Tally(tally: Tally) Int:
	return tally.total + 1

test "view and helper names stay apart from declared names":
	tally := Tally(1)
	copy := tally.clone()
	view: Counter := tally
	expect_false(view.count() != 1 or Counter_Tally(2).other != 2)?
	expect_false(copy.total != 1 or clone_Tally(tally) != 2)?

interface Reporter:
	fn describe() String
	fn receiver() String

impl Reporter for Tally:
	fn describe() String:
		return "describe {self.total}"

	fn receiver() String:
		return "receiver {self.total}"

test "operations named like generated view methods stay callable":
	reporter: Reporter := Tally(3)
	expect_false(
		(
			reporter.describe() != "describe 3"
			or reporter.receiver() != "receiver 3"
		)
	)?
