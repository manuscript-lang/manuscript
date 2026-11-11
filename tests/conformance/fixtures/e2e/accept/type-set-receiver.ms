// conform: tags=testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Meters:
	value: Int

type Feet:
	value: Int

type Length = Meters | Feet

fn Length.double() Self:
	return Self(value: self.value * 2)

fn Length.longer(other: Self) Self:
	if other.value > self.value: return other
	return self

test "a method declared on a set exists on every member":
	expect_equal(Meters(value: 4).double().value, 8)?
	expect_equal(Feet(value: 5).double().value, 10)?

test "Self is the receiving member":
	expect_equal(Meters(value: 4).longer(Meters(value: 9)).value, 9)?
	expect_equal(Feet(value: 7).longer(Feet(value: 2)).value, 7)?

test "the standard ordering methods are one declaration over a set":
	expect_equal((3).min(2), 2)?
	expect_equal((2.5).max(1.0), 2.5)?
	expect_equal("b".min("a"), "a")?
	expect_equal((15).clamp(0, 10), 10)?
