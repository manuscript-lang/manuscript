// conform: tags=alternatives,control-flow,formatter,generics,interfaces,interpolation,match,modules,parser,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/go-name-collisions.ms
import expect_equal, expect_false from "@std/test/test.ms"

type Spelled {
	x_ Int
	x Int
	a_b Int
	aB Int
}

interface Methods {
	fn foo_bar() Int
	fn fooBar() Int
}

fn Spelled.foo_bar() Int {
	return self.x_
}

fn Spelled.fooBar() Int {
	return self.x
}

fn string(value Int) Int {
	return value + 1
}

fn int(value Int) Int {
	return value + 2
}

fn float64(value Int) Int {
	return value + 3
}

fn nil(value Int) Int {
	return value + 4
}

test "field names that differ only in underscores stay distinct" {
	value := Spelled(1, 2, 3, 4)
	expect_false(value.x_ != 1 or value.x != 2 or value.a_b != 3 or value.aB != 4)?

	var clone = value.clone()
	clone.x_ = 9
	expect_false(value.x_ != 1 or clone.x_ != 9)?
	expect_equal(value, Spelled(1, 2, 3, 4))?
}

test "operation names that differ only in underscores stay distinct" {
	methods Methods := Spelled(1, 2, 3, 4)
	expect_false(methods.foo_bar() != 1 or methods.fooBar() != 2)?
}

test "functions named like Go predeclared identifiers still lower" {
	text := f"{string(1)}{int(1)}{float64(1)}{nil(1)}"
	floats := [1.5, 2.5]
	expect_false(text != "2345" or floats.length() != 2)?
}

type Box[T] {
	value T
}

type Box_Int {
	value String
}

enum Shape {
	Circle(radius Int)
	Square(side Int)
}

type Shape_Circle {
	radius String
}

fn side(shape Shape) Int {
	match shape {
		Circle(radius) => return radius
		Square(side) => return side
	}
}

test "declared names stay apart from instantiation and case names" {
	boxed := Box[Int](1)
	named := Box_Int("one")
	expect_false(boxed.value != 1 or named.value != "one")?
	expect_false(side(Shape.Circle(3)) != 3 or side(Shape.Square(4)) != 4)?
	expect_equal(Shape_Circle("r").radius, "r")?
}

interface Counter {
	fn count() Int
}

type Tally {
	total Int
}

fn Tally.count() Int {
	return self.total
}

type Counter_Tally {
	other Int
}

fn clone_Tally(tally Tally) Int {
	return tally.total + 1
}

test "view and helper names stay apart from declared names" {
	tally := Tally(1)
	copy := tally.clone()
	view Counter := tally
	expect_false(view.count() != 1 or Counter_Tally(2).other != 2)?
	expect_false(copy.total != 1 or clone_Tally(tally) != 2)?
}

interface Reporter {
	fn describe() String
	fn receiver() String
}

fn Tally.describe() String {
	return f"describe {self.total}"
}

fn Tally.receiver() String {
	return f"receiver {self.total}"
}

test "operations named like generated view methods stay callable" {
	reporter Reporter := Tally(3)
	expect_false(
		(
			reporter.describe() != "describe 3"
			or reporter.receiver() != "receiver 3"
		)
	)?
}
// expect-format: rewritten
// expect-formatted: import expect_equal, expect_false from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: type Spelled {
// expect-formatted: \tx_, x, a_b, aB Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: interface Methods {
// expect-formatted: \tfn foo_bar() Int
// expect-formatted: \tfn fooBar() Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Spelled.foo_bar() Int {
// expect-formatted: \treturn self.x_
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Spelled.fooBar() Int {
// expect-formatted: \treturn self.x
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn string(value Int) Int {
// expect-formatted: \treturn value + 1
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn int(value Int) Int {
// expect-formatted: \treturn value + 2
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn float64(value Int) Int {
// expect-formatted: \treturn value + 3
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn nil(value Int) Int {
// expect-formatted: \treturn value + 4
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "field names that differ only in underscores stay distinct" {
// expect-formatted: \tvalue := Spelled(1, 2, 3, 4)
// expect-formatted: \texpect_false(value.x_ != 1 or value.x != 2 or value.a_b != 3 or value.aB != 4)?
// expect-formatted:
// expect-formatted: \tvar clone = value.clone()
// expect-formatted: \tclone.x_ = 9
// expect-formatted: \texpect_false(value.x_ != 1 or clone.x_ != 9)?
// expect-formatted: \texpect_equal(value, Spelled(1, 2, 3, 4))?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "operation names that differ only in underscores stay distinct" {
// expect-formatted: \tmethods Methods := Spelled(1, 2, 3, 4)
// expect-formatted: \texpect_false(methods.foo_bar() != 1 or methods.fooBar() != 2)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "functions named like Go predeclared identifiers still lower" {
// expect-formatted: \ttext := f"{string(1)}{int(1)}{float64(1)}{nil(1)}"
// expect-formatted: \tfloats := [1.5, 2.5]
// expect-formatted: \texpect_false(text != "2345" or floats.length() != 2)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Box[T] {
// expect-formatted: \tvalue T
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Box_Int {
// expect-formatted: \tvalue String
// expect-formatted: }
// expect-formatted:
// expect-formatted: enum Shape {
// expect-formatted: \tCircle(radius Int)
// expect-formatted: \tSquare(side Int)
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Shape_Circle {
// expect-formatted: \tradius String
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn side(shape Shape) Int {
// expect-formatted: \tmatch shape {
// expect-formatted: \t\tCircle(radius) => return radius
// expect-formatted: \t\tSquare(side) => return side
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "declared names stay apart from instantiation and case names" {
// expect-formatted: \tboxed := Box[Int](1)
// expect-formatted: \tnamed := Box_Int("one")
// expect-formatted: \texpect_false(boxed.value != 1 or named.value != "one")?
// expect-formatted: \texpect_false(side(Shape.Circle(3)) != 3 or side(Shape.Square(4)) != 4)?
// expect-formatted: \texpect_equal(Shape_Circle("r").radius, "r")?
// expect-formatted: }
// expect-formatted:
// expect-formatted: interface Counter {
// expect-formatted: \tfn count() Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Tally {
// expect-formatted: \ttotal Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Tally.count() Int {
// expect-formatted: \treturn self.total
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Counter_Tally {
// expect-formatted: \tother Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn clone_Tally(tally Tally) Int {
// expect-formatted: \treturn tally.total + 1
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "view and helper names stay apart from declared names" {
// expect-formatted: \ttally := Tally(1)
// expect-formatted: \tcopy := tally.clone()
// expect-formatted: \tview Counter := tally
// expect-formatted: \texpect_false(view.count() != 1 or Counter_Tally(2).other != 2)?
// expect-formatted: \texpect_false(copy.total != 1 or clone_Tally(tally) != 2)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: interface Reporter {
// expect-formatted: \tfn describe() String
// expect-formatted: \tfn receiver() String
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Tally.describe() String {
// expect-formatted: \treturn f"describe {self.total}"
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Tally.receiver() String {
// expect-formatted: \treturn f"receiver {self.total}"
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "operations named like generated view methods stay callable" {
// expect-formatted: \treporter Reporter := Tally(3)
// expect-formatted: \texpect_false(
// expect-formatted: \t\t(
// expect-formatted: \t\t\treporter.describe() != "describe 3"
// expect-formatted: \t\t\tor reporter.receiver() != "receiver 3"
// expect-formatted: \t\t)
// expect-formatted: \t)?
// expect-formatted: }
