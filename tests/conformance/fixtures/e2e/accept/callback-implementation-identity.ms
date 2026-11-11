// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Box[T]:
	value: T

interface Forward:
	fn forward() Int

interface Reverse:
	fn reverse() Int

impl Forward for Box[fn(Int) Int]:
	fn forward() Int: 1

impl Forward for Box[fn(var Int) Int]:
	fn forward() Int: 2

impl Reverse for Box[fn(var Int) Int]:
	fn reverse() Int: 4

impl Reverse for Box[fn(Int) Int]:
	fn reverse() Int: 3

fn identity(value: Int) Int: value

fn increment(var value: Int) Int:
	value += 1
	return value

fn forward[T: Forward](value: T) Int: value.forward()

fn reverse[T: Reverse](value: T) Int: value.reverse()

test "callback modes select their exact implementation in either declaration order":
	plain := Box[fn(Int) Int](identity)
	changing := Box[fn(var Int) Int](increment)
	expect_equal(plain.forward(), 1)?
	expect_equal(changing.forward(), 2)?
	expect_equal(plain.reverse(), 3)?
	expect_equal(changing.reverse(), 4)?
	expect_equal(forward(plain), 1)?
	expect_equal(forward(changing), 2)?
	expect_equal(reverse(plain), 3)?
	expect_equal(reverse(changing), 4)?

test "interface views and method values retain exact callback identity":
	plain := Box[fn(Int) Int](identity)
	changing := Box[fn(var Int) Int](increment)
	first: Forward := plain
	second: Forward := changing
	third: Reverse := plain
	fourth: Reverse := changing
	expect_equal(first.forward(), 1)?
	expect_equal(second.forward(), 2)?
	expect_equal(third.reverse(), 3)?
	expect_equal(fourth.reverse(), 4)?

	read_plain := plain.forward
	read_changing := changing.forward
	expect_equal(read_plain(), 1)?
	expect_equal(read_changing(), 2)?
