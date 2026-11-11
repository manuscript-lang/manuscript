import expect_equal, expect_false from "@std/test/test.ms"

type Cell:
	value: Int

fn increment(value: Int = 3) Int:
	return value + 1

fn combine(first: Int = 2, second: Int, third: Int = first + second) Int:
	return first + second + third

fn identity[T](value: T, fallback: T = value) T:
	return fallback

fn ordered(
	seed: Int,
	first: Int = seed * 10 + 3,
	second: Int = first * 10 + 4,
	third: Int = 0
) Int:
	return second * 10 + 5 + third

fn unit_default() Unit:
	return unit

fn unit_value(value: Unit = unit_default()) Unit:
	return value

fn optional(value: Int? = 3) Int?:
	return value

fn fail() Int!Error:
	return error(Error("default failure"))

fn propagate(value: Int = fail()?) Int!Error:
	return ok(value)

interface Add:
	fn add(value: Int) Int

type Offset:
	value: Int

fn Offset.add(value: Int = self.value) Int:
	return self.value + value

interface Read[T]:
	fn read(value: T) T

type Box[T: Clonable]:
	value: T

fn Box[T].read(value: T = self.value.clone()) T:
	return value

test "omitted and explicit defaults":
	(increment() != 4 or increment(7) != 8 or increment(value: 0) != 1) | expect_false?
	(combine(second: 5) != 14 or combine(third: 0, second: 5, first: 0) != 5) | expect_false?
	(identity(value: 9) != 9 or identity(value: 9, fallback: 4) != 4) | expect_false?
	unit_value(unit) | expect_equal(unit)?
	unit_value() | expect_equal(unit)?
	(optional(value: none).is_some() or optional() != 3) | expect_false?
	(
		(
			propagate() != Result[Int, Error].error(
				Error("default failure")
			)
			or propagate(7) != Result[Int, Error].ok(7)
		)
	) | expect_false?

test "default evaluation order and repeated calls":
	ordered(0) | expect_equal(345)?
	ordered(0, third: 1) | expect_equal(346)?
	ordered(0, second: 7) | expect_equal(75)?
	ordered(1, first: 2) | expect_equal(245)?
	ordered(0) | expect_equal(345)?

test "function values and captures":
	copy := increment
	copied := copy
	copied() | expect_equal(4)?

	typed: fn(Int) Int := increment
	typed(2) | expect_equal(3)?

	offset := 5
	callback := fn(value: Int = offset):
		return value
	(callback() != 5 or callback(0) != 0) | expect_false?

	nested := fn(first: Int = 6, second: Int = first + 1):
		return second
	nested() | expect_equal(7)?

test "implementation and bound method defaults":
	offset := Offset(4)
	bound := offset.add
	(offset.add() != 8 or bound() != 8 or bound(0) != 4) | expect_false?

	view: Add := offset
	view.add(2) | expect_equal(6)?

	box := Box[String]("boxed")
	box.read() | expect_equal("boxed")?
