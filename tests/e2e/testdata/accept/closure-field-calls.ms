import expect_equal from "@std/test/test.ms"

type Scaler:
	scale: fn(Int) Int

type Mutable:
	scale: fn(Int) Int

test "a closure field set to one lambda everywhere still calls it":
	a := Scaler(scale: fn(x: Int) Int: x + x)
	b := Scaler(scale: fn(x: Int) Int: x + x)
	try expect_equal(a.scale(21), 42)
	try expect_equal(b.scale(4), 8)

test "closure fields set to different lambdas keep their own behavior":
	a := Scaler(scale: fn(x: Int) Int: x * 3)
	b := Scaler(scale: fn(x: Int) Int: x * 5)
	offset := 100
	c := Scaler(scale: fn(x: Int) Int: x + offset)
	try expect_equal(a.scale(2), 6)
	try expect_equal(b.scale(2), 10)
	try expect_equal(c.scale(2), 102)

test "assigning a closure field changes later calls":
	var m = Mutable(scale: fn(x: Int) Int: x + 1)
	try expect_equal(m.scale(1), 2)
	m.scale = fn(x: Int) Int: x * 10
	try expect_equal(m.scale(1), 10)
