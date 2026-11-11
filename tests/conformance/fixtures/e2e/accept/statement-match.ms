// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

enum Shape:
	Circle(r: Int)
	Rect(w: Int, h: Int)
	Dot

fn area(shape: Shape) Int:
	match shape:
		Circle(r): return 3 * r * r
		Rect(w, h): return w * h
		Dot: return 0

	return -1

fn first_positive(values: List[Int?]) Int:
	var index = 0

	while index < values.length():
		item := values.get(index)
		index += 1

		match item:
			none: continue
			value:
				if value > 0: return value

	return -1

fn nested(rows: List[List[Int?]]) Int:
	var total = 0

	for row in rows:
		for item in row:
			match item:
				none: break
				value: total += value

		total += 1000

	return total

fn side_effects(shape: Shape) Int:
	var count = 0

	match shape:
		Circle(r):
			count += r
		_:
			count += 100

	return count

test "statement match returns from the enclosing function":
	expect_equal(area(Shape.Circle(2)), 12)?
	expect_equal(area(Shape.Rect(3, 4)), 12)?
	expect_equal(area(Shape.Dot), 0)?

test "statement match controls the nearest loop":
	values: List[Int?] := [none, 0, 5, 9]
	expect_equal(first_positive(values), 5)?
	expect_equal(first_positive([none, -1]), -1)?

	rows: List[List[Int?]] := [[1, none, 100], [2, 3]]
	expect_equal(nested(rows), 2006)?

test "statement match arms assign enclosing locals":
	expect_equal(side_effects(Shape.Circle(7)), 7)?
	expect_equal(side_effects(Shape.Dot), 100)?
