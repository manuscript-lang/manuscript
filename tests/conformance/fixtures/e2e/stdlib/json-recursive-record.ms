// conform: tags=optional,records,stdlib-json,testing,tier-io,try-result
// conform: phase=test
import stringify, parse from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"
type Link:
	value: Int
	next: Link?
test "recursive record round trips through JSON":
	text := stringify(Link(value: 2, next: Link(value: 1, next: none)))?
	expect_equal(text, "{\"value\":2,\"next\":{\"value\":1}}")?
	back := parse[Link](text)?
	expect_equal(back.next.get().value, 1)?
