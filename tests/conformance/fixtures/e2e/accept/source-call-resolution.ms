// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Counter:
	value: Int

impl Counter:
	fn next(amount: Int = 1) Counter: Counter(self.value + amount)

	fn identity[T](value: T) T: value

	fn to_string(prefix: String) String: "{prefix}{self.value}"

fn make(create: fn() Int) Counter: Counter(create())

test "source chains keep callbacks, defaults and bound methods":
	start := 3
	value := make(fn: start).next().next(amount: 2).next().next()
	expect_equal(value.value, 8)?

	advance := value.next
	expect_equal(advance().value, 9)?
	expect_equal(value.identity(7), 7)?
	expect_equal(value.identity[String]("ok"), "ok")?

test "native arity fallback still selects the source method":
	value := Counter(4)
	expect_equal(value.to_string("count="), "count=4")?
	expect_equal(value.to_string().is_empty(), false)?
