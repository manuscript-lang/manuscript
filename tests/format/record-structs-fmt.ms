// conform: tags=control-flow,formatter,interpolation,lists,modules,numbers,parser,records,sets,stdlib-testing,strings,testing,tier-core,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/record-structs.ms
import expect_equal, expect_false, expect_not_equal, fail from "@std/test/test.ms"

type Point {
	x Int
	y Int
}

type Shape {
	name String
	weight Float
	solid Bool
	corner Point
	tags List[String]
}

type Sized {
	width Int
	height Int = 2
}

fn area(shape Sized) Int => shape.width * shape.height

fn shifted(point Point, by Int) Point {
	return Point(point.x + by, point.y + by)
}

test "struct records read write compare format and clone" {
	a := Point(1, 2)
	var b = Point(y: 2, x: 1)
	expect_equal(a, b)?
	b.x = 5
	expect_not_equal(a, b)?
	expect_false(not (a.x == 1 and b.x == 5 and shifted(a, 3).y == 5))?

	var copy = a.clone()
	copy.y = 9
	expect_false(not (a.y == 2 and copy.y == 9))?
	if f"{a}" != "Point(x: 1, y: 2)" { return fail(f"format changed: {a}") }
}

test "struct records with mixed field types" {
	var shape = Shape("disc", 1.5, solid: true, corner: Point(0, 0), tags: ["a"])
	shape.weight *= 2.0
	shape.name = f"{shape.name}!"
	shape.corner.x = 4
	shape.tags.append("b")
	expect_false(
		not (
			shape.weight == 3.0
			and shape.name == "disc!"
			and shape.solid
			and shape.corner.x == 4
			and shape.tags.length() == 2
		)
	)?
}

test "struct records as keys and defaults" {
	var set Set[Point] = Set[Point]()
	set.add(Point(1, 1))
	set.add(Point(1, 1))
	set.add(Point(2, 1))
	expect_equal(set.length(), 2)?

	sized := Sized(3)
	expect_false(area(sized) != 6 or area(Sized(3, 5)) != 15)?
}
// expect-format: rewritten
// expect-formatted: import expect_equal, expect_false, expect_not_equal, fail from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: type Point {
// expect-formatted: \tx, y Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Shape {
// expect-formatted: \tname String
// expect-formatted: \tweight Float
// expect-formatted: \tsolid Bool
// expect-formatted: \tcorner Point
// expect-formatted: \ttags List[String]
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Sized {
// expect-formatted: \twidth Int
// expect-formatted: \theight Int = 2
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn area(shape Sized) Int => shape.width * shape.height
// expect-formatted:
// expect-formatted: fn shifted(point Point, by Int) Point {
// expect-formatted: \treturn Point(point.x + by, point.y + by)
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "struct records read write compare format and clone" {
// expect-formatted: \ta := Point(1, 2)
// expect-formatted: \tvar b = Point(y: 2, x: 1)
// expect-formatted: \texpect_equal(a, b)?
// expect-formatted: \tb.x = 5
// expect-formatted: \texpect_not_equal(a, b)?
// expect-formatted: \texpect_false(not (a.x == 1 and b.x == 5 and shifted(a, 3).y == 5))?
// expect-formatted:
// expect-formatted: \tvar copy = a.clone()
// expect-formatted: \tcopy.y = 9
// expect-formatted: \texpect_false(not (a.y == 2 and copy.y == 9))?
// expect-formatted: \tif f"{a}" != "Point(x: 1, y: 2)" { return fail(f"format changed: {a}") }
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "struct records with mixed field types" {
// expect-formatted: \tvar shape = Shape("disc", 1.5, solid: true, corner: Point(0, 0), tags: ["a"])
// expect-formatted: \tshape.weight *= 2.0
// expect-formatted: \tshape.name = f"{shape.name}!"
// expect-formatted: \tshape.corner.x = 4
// expect-formatted: \tshape.tags.append("b")
// expect-formatted: \texpect_false(
// expect-formatted: \t\tnot (
// expect-formatted: \t\t\tshape.weight == 3.0
// expect-formatted: \t\t\tand shape.name == "disc!"
// expect-formatted: \t\t\tand shape.solid
// expect-formatted: \t\t\tand shape.corner.x == 4
// expect-formatted: \t\t\tand shape.tags.length() == 2
// expect-formatted: \t\t)
// expect-formatted: \t)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "struct records as keys and defaults" {
// expect-formatted: \tvar set Set[Point] = Set[Point]()
// expect-formatted: \tset.add(Point(1, 1))
// expect-formatted: \tset.add(Point(1, 1))
// expect-formatted: \tset.add(Point(2, 1))
// expect-formatted: \texpect_equal(set.length(), 2)?
// expect-formatted:
// expect-formatted: \tsized := Sized(3)
// expect-formatted: \texpect_false(area(sized) != 6 or area(Sized(3, 5)) != 15)?
// expect-formatted: }
