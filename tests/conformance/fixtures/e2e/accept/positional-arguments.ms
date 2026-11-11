// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_false from "@std/test/test.ms"

fn subtract(amount: Int, deduction: Int) Int: amount - deduction

fn first[T](left: T, right: T) T: left

fn pick[T](items: List[T], keep: fn(T) Bool) T?:
	for item in items:
		if keep(item): return item
	return none

type Counter:
	value: Int = 0

fn mark(var counter: Counter, value: Int) Int:
	counter.value = counter.value * 10 + value
	return value

fn chosen(var counter: Counter) fn(Int, Int) Int:
	mark(var counter, 1)
	return subtract

fn ordered(
	var counter: Counter,
	first: Int = mark(counter, 3),
	second: Int = mark(counter, 4),
	third: Int = 0,
) Int:
	counter.value = counter.value * 10 + 5
	return first + second + third

type Record[T]:
	first: T
	second: T = first

enum Choice[T]:
	Pair(first: T, second: T)

interface Subtract:
	fn subtract(amount: Int, deduction: Int) Int

type Offset:
	value: Int

fn Offset.subtract(amount: Int, deduction: Int = self.value) Int: amount - deduction

fn apply(callback: fn(Int, Int) Int, input: Int) Int: callback(input, 2)

fn optional(value: Int?, fallback: Int = 0) Int: value.get(fallback)

fn default_before_required(first: Int = 9, second: Int) Int: first - second

test "positional labeled mixed and identifier calls":
	amount := 10
	deduction := 3
	expect_false(
		(
			subtract(10, 3) != 7
			or subtract(amount: 10, deduction: 3) != 7
			or subtract(deduction: 3, amount: 10) != 7
			or subtract(deduction: 3, 10) != 7
			or subtract(10, deduction: 3) != 7
			or subtract(deduction, amount) != -7
			or subtract((deduction), (amount)) != -7
			or subtract(amount + 1, deduction) != 8
		)
	)?
	expect_false(
		(
			default_before_required(second: 2) != 7
			or default_before_required(second: 2, 5) != 3
		)
	)?

test "generic calls constructors and callback inference":
	expect_false(first(3, 4) != 3 or first[Int](right: 4, 3) != 3)?
	expect_equal(pick([1, 2], fn item: item > 1).get(0), 2)?
	expect_equal(pick(keep: fn item: item > 1, [1, 2]).get(0), 2)?

	record := Record(3)
	explicit := Record[Int](second: 4, 3)
	expect_false((record.second != 3 or explicit.first != 3 or explicit.second != 4))?

	first := 4
	second := 3
	shorthand := Record(second, first)
	expect_false(shorthand.first != 3 or shorthand.second != 4)?

	match Choice.Pair(second: "right", "left"):
		Pair(left, right):
			expect_false(left != "left" or right != "right")?

	match Choice[Int].Pair(3, 4):
		Pair(left, right):
			expect_false(left != 3 or right != 4)?

	sum := [1, 2, 3].fold(0, fn total, item: total + item)
	reordered_sum := [1, 2, 3].fold(step: fn total, item: total + item, 0)
	explicit_sum := [1, 2, 3].fold[Int](0, fn total, item: total + item)
	expect_false((sum != 6 or reordered_sum != 6 or explicit_sum != 6))?
	expect_false(optional(4) != 4 or optional(none, 2) != 2)?

test "methods native APIs function values and contextual labels":
	offset := Offset(3)
	bound := offset.subtract
	view: Subtract := offset
	expect_false(
		(
			offset.subtract(10) != 7
			or bound(10, 2) != 8
			or view.subtract(deduction: 2, 10) != 8
		)
	)?

	copied := subtract
	typed: fn(Int, Int) Int := subtract
	var mutable = subtract
	expect_false((copied(10, 3) != 7 or typed(10, 3) != 7 or mutable(10, 3) != 7))?

	contextual: fn(Int, Int) Int := fn x, y: x - y
	expect_false(
		(
			contextual(10, 3) != 7
			or contextual(10, 3) != 7
			or apply(fn x, y: x - y, 10) != 8
		)
	)?

	var memo = Map[Int, Int]()
	memo.add(1, 7)

	add := memo.add
	add(value: 8, 2)
	expect_false(memo[1] != 7 or memo[2] != 8)?
	expect_equal("abcd".slice(1, 3).get(), "bc")?

test "written order before omitted defaults and body":
	var counter = Counter()
	total := ordered(var counter, third: mark(var counter, 1), mark(var counter, 2))
	expect_false(total != 7 or counter.value != 1245)?
	counter.value = 0

	reordered := first(right: mark(var counter, 2), mark(var counter, 1))
	expect_false(reordered != 1 or counter.value != 21)?
	counter.value = 0

	record := Record(second: mark(var counter, 2), mark(var counter, 1))
	expect_false((record.first != 1 or record.second != 2 or counter.value != 21))?

	var early = 7
	selected := first(
		early,
		match present(0):
			_value:
				early = 9
				0
			none: 0
	)
	expect_equal(selected, 7)?

	var receiver = Offset(3)
	receiver = Offset(9)

	result := receiver.subtract(10)
	expect_equal(result, 1)?

test "callable expression precedes positional arguments":
	var counter = Counter()
	result := chosen(var counter)(mark(var counter, 2), mark(var counter, 3))
	expect_false(result != -1 or counter.value != 123)?

test "a mutable callable value is called in place":
	var selected = subtract
	selected = fn(amount: Int, deduction: Int) Int: (amount + deduction)

	result := selected(10, 3)
	expect_equal(result, 13)?

fn present[T](value: T) T?:
	return value
