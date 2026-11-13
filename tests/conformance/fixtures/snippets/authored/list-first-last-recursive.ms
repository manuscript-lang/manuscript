// conform: tags=stdlib-collections,testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Node:
	v: Int
	next: Node?

fn chain() List[Node]:
	return [Node(v: 1, next: Node(v: 2, next: none)), Node(v: 3, next: none)]

test "first and last of a list of recursive nodes":
	xs := chain()
	a := xs.first()
	b := xs.last()
	expect_equal(a?.v, 1)?
	expect_equal(b?.v, 3)?
	expect_equal(xs.length(), 2)?

	empty: List[Node] := []
	expect_equal(empty.first()?.v, none)?

test "first of a temporary list of recursive nodes":
	expect_equal(chain().first()?.v, 1)?
	expect_equal(chain().last()?.v, 3)?
