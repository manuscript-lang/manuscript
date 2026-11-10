import expect_equal from "@std/test/test.ms"

type Link:
	next: Link?
	value: Int

fn make() Link:
	return Link(Link(Link(none, 3), 2), 1)

test "two chains through record payloads share one interpolation":
	head := make()
	text := "{head.next?.value} {head.next?.value} {head.next?.next?.value}"
	try expect_equal(text, "some(2) some(2) some(3)")

test "a chain on a call result keeps its temporary until the statement ends":
	text := "{make().next?.value} {make().next?.next?.value}"
	try expect_equal(text, "some(2) some(3)")
