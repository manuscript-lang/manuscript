// conform: tags=testing
// conform: phase=test
import (
	promise from "@std/concurrency/promise.ms",
	Mock1 from "@std/test/mock.ms",
	expect_equal, fake from "@std/test/test.ms",
	Timestamp, now from "@std/time.ms",
)

// ms: effect shop.read
fn price(item: String) Int:
	return 100

fn total(items: List[String]) Int:
	var sum = 0
	for i in items:
		sum += price(i)
	return sum

test "plain fake":
	expect_equal(total(["a", "b"]), 200)?

	fake(
		price,
		fn item: 7,
		fn:
			expect_equal(total(["a", "b"]), 14)?
			return ok()
	)?

	expect_equal(total(["a"]), 100)?

test "mock inside fake":
	var m = Mock1[String, Int](fallback: 5)
	m.returns_once(1)

	fake(
		price,
		fn item: m.call(item),
		fn:
			expect_equal(total(["a", "b"]), 6)?
			return ok()
	)?

	m.expect_called_times(2)?
	m.expect_called_with("b")?

// ms: effect shop.read
fn stamp() Int:
	return 1

// ms: effect shop.read
fn quiet(x: Int) Int:
	return x

test "fake in a promise":
	fake(
		stamp,
		fn: 9,
		fn:
			p := promise(fn: ok(stamp() + 1))
			expect_equal(p.wait()?, 10)?
			return ok()
	)?

test "nested, innermost wins":
	fake(
		quiet,
		fn x: x + 1,
		fn:
			fake(
				quiet,
				fn x: x + 100,
				fn:
					expect_equal(quiet(1), 101)?
					return ok()
			)?

			expect_equal(quiet(1), 2)?
			return ok()
	)?

	expect_equal(quiet(1), 1)?

test "stdlib function":
	fake(
		now,
		fn: Timestamp(seconds: 86400, nanos: 0),
		fn:
			expect_equal(now().seconds, 86400)?
			return ok()
	)?

test "a replacement can call the original":
	fake(
		quiet,
		fn x: quiet(x) * 10,
		fn:
			expect_equal(quiet(4), 40)?
			return ok()
	)?

	expect_equal(quiet(4), 4)?

type Shop:
	rate: Int

// ms: effect shop.read
fn Shop.price(item: String) Int:
	return self.rate

fn shop_total(shop: Shop) Int:
	return shop.price("a") + shop.price("b")

test "a method that declares an effect, for every object":
	shop := Shop(3)
	expect_equal(shop_total(shop), 6)?

	fake(
		shop.price,
		fn item: 10,
		fn:
			expect_equal(shop_total(Shop(99)), 20)?
			return ok()
	)?

	expect_equal(shop_total(shop), 6)?
