// conform: tags=testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Rows = List[Int]
type Handler = fn(Int) Int
type Maybe[T] = T?

fn total(rows: Rows) Int:
	return rows.fold(0, fn sum, x: sum + x)

fn twice(step: Handler, x: Int) Int:
	return step(step(x))

fn first(values: Maybe[Int]) Int:
	if v := values: return v
	return -1

test "an alias and its target are the same type":
	numbers: List[Int] := [1, 2, 3]
	expect_equal(total(numbers), 6)?

	rows: Rows := [4, 5]
	expect_equal(rows.length(), 2)?
	expect_equal(twice(fn x: x * 3, 2), 18)?
	expect_equal(first(7), 7)?
	expect_equal(first(none), -1)?
