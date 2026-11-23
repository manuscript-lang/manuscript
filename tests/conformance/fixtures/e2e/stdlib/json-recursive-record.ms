// conform: tags=optional,records,stdlib-json,testing,tier-io,try-result
// conform: phase=test
import (
	panic from "@std/core.ms",
	parse, stringify from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",
)

type Link:
	value: Int
	next: Link?

test "recursive record round trips through JSON":
	text := stringify(Link(value: 2, next: Link(value: 1, next: null)))?
	expect_equal(text, "{\"value\":2,\"next\":{\"value\":1}}")?

	back := parse[Link](text)?
	expect_equal((back.next or panic("called Optional.get() on null")).value, 1)?
