// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Mock0, Mock1, Mock2 from "@std/test/mock.ms",
	expect_equal, expect_error, expect_true from "@std/test/test.ms",
)

interface Mailer:
	fn send(to: String, subject: String) Int

type Spying:
	mock: Mock2[String, String, Int]

fn var Spying.send(to: String, subject: String) Int:
	return self.mock.call(to, subject)

fn greet(m: fn(String) Int, names: List[String]) Int:
	var total = 0
	for n in names:
		total += m(n)
	return total

test "records and answers":
	var m = Mock1[String, Int](fallback: 1)
	m.returns_once(10)

	total := greet(fn n: m.call(n), ["ada", "sam", "lin"])
	expect_equal(total, 12)?
	m.expect_called_times(3)?
	m.expect_called_with("sam")?
	m.expect_last_called_with("lin")?
	expect_equal(m.calls, ["ada", "sam", "lin"])?

test "failures report":
	var m = Mock1[String, Int](fallback: 0)
	m.call("x")
	expect_true(m.expect_called_with("y").is_error())?
	expect_true(m.expect_called_times(2).is_error())?
	m.reset()
	m.expect_not_called()?

test "two args and zero args":
	var m = Mock2[String, String, Int](fallback: 7)
	expect_equal(m.call("a", "b"), 7)?
	m.expect_called_with("a", "b")?

	var z = Mock0[Bool](fallback: true)
	expect_equal(z.call(), true)?
	z.expect_called_times(1)?
