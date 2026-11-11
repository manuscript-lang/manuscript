// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn read[T: Reader[Int]](value: T) Int: return value.read()

interface Reader[A]:
	fn read() A

type Counter:
	value: Int

impl Reader[Int] for Counter:
	fn read() Int: return self.value

test "a forward generic interface bound dispatches with its argument":
	expect_equal(read(Counter(7)), 7)?
