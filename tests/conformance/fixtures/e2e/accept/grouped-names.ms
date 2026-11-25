// conform: tags=records,testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Rect {
	width, height Int
	label String = "rect"
	x, y Float = 0.5
}

enum Shape {
	Box(width, height Int)
	Dot
}

fn area(width, height Int) Int => width * height

fn scaled(w, h Int, factor Float = 2.0) Float => w.to_float() * h.to_float() * factor

fn sides(s Shape) Int {
	match s {
		Box(w, h) => return w + h
		Dot => return 0
	}
}

test "a record shares one type across grouped fields" {
	r := Rect(width: 2, height: 3)
	expect_equal(area(r.width, r.height), 6)?
	expect_equal(r.label, "rect")?
	expect_equal(r.y, 0.5)?
}

test "a function shares one type across grouped parameters" {
	expect_equal(scaled(2, 3), 12.0)?
	expect_equal(scaled(2, 3, factor: 1.0), 6.0)?
}

test "an enum payload shares one type across grouped names" {
	expect_equal(sides(Shape.Box(1, 2)), 3)?
	expect_equal(sides(Shape.Dot), 0)?
}
