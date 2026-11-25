// conform: tags=lists,maps,tier-core,testing
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal from "@std/test/test.ms",
)

// A key that is not a plain variable runs before the value, so each reads the optional
// in order and the last read takes it.
type Person {
	id Int
	name String
}

test "a key and a value both read an owned optional" {
	var queue List[Person] = [Person(id: 1, name: "ada")]
	var by_id Map[Int, Person] = {}

	while queue.length() > 0 {
		p := queue.pop()
		by_id[(p or panic("called Optional.get() on null")).id] = (
			p
			or panic("called Optional.get() on null")
		)
	}

	expect_equal(by_id.length(), 1)?
	expect_equal(by_id.get_or(1, Person(id: 0, name: "")).name, "ada")?
}
