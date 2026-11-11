// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn identity[T](value: T) T:
	return value

fn increment(var value: Int) Unit:
	value += 1

fn peek(value: Int) Int:
	return value

test "an explicit generic argument can be a function type with a var parameter":
	change := identity[fn(var Int) Unit](increment)
	var value = 1
	change(var value)
	expect_equal(value, 2)?

test "a var function type nests inside another generic argument":
	boxed: List[fn(var Int) Unit] := identity[List[fn(var Int) Unit]]([increment])
	var value = 1
	boxed[0](var value)
	expect_equal(value, 2)?

test "plain function types and indexed values still parse as before":
	same := identity[fn(Int) Int](peek)
	table := [1, 2, 3]
	expect_equal(same(table[1]), 2)?

	var inferred = 5
	identity(increment)(var inferred)
	expect_equal(inferred, 6)?
