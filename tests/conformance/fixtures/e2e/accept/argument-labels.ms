// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	sqrt from "@std/math/math.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

fn increment(value: Int) Int:
	return value + 1

fn identity[T](value: T) T:
	return value

fn sum(values: List[Int]) Int:
	var total = 0
	for value in values:
		total += value
	return total

fn apply(transform: fn(Int) Int) Int:
	return transform(4)

fn select() fn(Int) Int:
	return increment

fn subtract(amount: Int, deduction: Int) Int:
	return amount - deduction

interface Increment:
	fn apply(value: Int) Int

type Offset:
	delta: Int

fn Offset.apply(value: Int) Int:
	return value + self.delta

type Counter:
	value: Int

fn next(var state: Counter) Int:
	value := state.value
	state.value = value + 1
	return value

fn prepare_receiver(var state: Counter) Offset!:
	next(var state) | expect_equal(0)?
	return ok(Offset(2))

fn prepare_function(var state: Counter) (fn(Int) Int)!:
	next(var state) | expect_equal(4)?
	return ok(increment)

fn absent(value: Int?) Bool:
	missing: Int? := none
	return value == missing

test "optional labels on single-parameter functions":
	increment(3) | expect_equal(increment(value: 3))?

	multiline := increment(3)
	multiline | expect_equal(4)?
	identity(7) | expect_equal(7)?
	identity[Int](7) | expect_equal(7)?
	(identity(true)) | expect_true?
	identity(unit) | expect_equal(unit)?
	(absent(none)) | expect_true?
	"{increment(3)}" | expect_equal("4")?
	select()(5) | expect_equal(6)?

	specialized := identity[Int]
	specialized(8) | expect_equal(8)?

	closure := fn(value: Int):
		return value * 2
	closure(3) | expect_equal(6)?
	apply(closure) | expect_equal(8)?

	result := apply(fn value: return value + 2)
	result | expect_equal(6)?
	subtract(deduction: increment(1), amount: increment(8)) | expect_equal(7)?

test "optional labels on methods and native functions":
	offset := Offset(3)
	offset.apply(4) | expect_equal(7)?

	view: Increment := offset
	view.apply(4) | expect_equal(7)?

	method := view.apply
	method(5) | expect_equal(8)?
	sqrt(9.0) | expect_equal(3.0)?

	native := sqrt
	native(16.0) | expect_equal(4.0)?
	sum([]) | expect_equal(0)?
	sum([1, 2, 3]) | expect_equal(6)?

	var chain_1 = ([1, 2, 3])
	chain_1.reverse()
	chain_1 | expect_equal([3, 2, 1])?

	var chain_2 = [1, 2]
	chain_2.append(3)
	chain_2 | expect_equal([1, 2, 3])?

	lookup := [4, 5].get
	lookup(1) | expect_equal(5)?
	[4, 5].get(0) | expect_equal(4)?

test "omitted labels preserve evaluation order":
	var state = Counter(value: 0)
	(prepare_receiver(var state)?).apply(next(var state)) | expect_equal(3)?
	state.value | expect_equal(2)?
	subtract(deduction: next(var state), amount: next(var state)) | expect_equal(1)?
	state.value | expect_equal(4)?
	(prepare_function(var state)?)(next(var state)) | expect_equal(6)?
	state.value | expect_equal(6)?
	sum([next(var state), next(var state)]) | expect_equal(13)?
	state.value | expect_equal(8)?
