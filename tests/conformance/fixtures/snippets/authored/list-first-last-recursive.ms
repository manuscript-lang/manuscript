// conform: tags=stdlib-collections,testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Node {
	v Int
	next Node?
}

fn value_of(n Node?) Int? {
	return n?.v
}

fn next_value_of(n Node?) Int? {
	return n?.next?.v
}

fn chain() List[Node] {
	return [Node(v: 1, next: Node(v: 2, next: null)), Node(v: 3, next: null)]
}

test "first and last of a list of recursive nodes" {
	xs := chain()
	a := xs.first()
	b := xs.last()
	expect_equal(value_of(a), 1)?
	expect_equal(value_of(b), 3)?
	expect_equal(xs.length(), 2)?

	empty List[Node] := []
	expect_equal(value_of(empty.first()), null)?
}

test "first of a temporary list of recursive nodes" {
	expect_equal(value_of(chain().first()), 1)?
	expect_equal(value_of(chain().last()), 3)?
}

fn node_at(xs List[Node], i Int) Node? {
	return xs.get(i)
}

test "get and a map entry of recursive nodes borrow in place" {
	xs := chain()
	expect_equal(value_of(node_at(xs, 1)), 3)?
	expect_equal(value_of(node_at(xs, -1)), 3)?

	m Map[String, Node] := {"a": xs[0].clone()}
	expect_equal(value_of(m.get("a")), 1)?
	expect_equal(value_of(m.get("b")), null)?
	expect_equal(next_value_of(m.get("a")), 2)?
}
