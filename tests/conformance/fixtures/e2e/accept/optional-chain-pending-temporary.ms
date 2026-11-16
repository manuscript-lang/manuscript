// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Link:
	value: Int
	next: Link?

fn make() Link:
	return Link(next: Link(next: Link(next: none, value: 3), value: 2), value: 1)

test "two chains through record payloads share one interpolation":
	head := make()
	text := f"{head.next?.value} {head.next?.value} {head.next?.next?.value}"
	expect_equal(text, "some(2) some(2) some(3)")?

test "a chain on a call result keeps its temporary until the statement ends":
	text := f"{make().next?.value} {make().next?.next?.value}"
	expect_equal(text, "some(2) some(3)")?
