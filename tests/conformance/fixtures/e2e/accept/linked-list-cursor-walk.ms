// conform: tags=control-flow,lists,testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Node:
	value: Int
	next: Node?

fn build(count: Int) Node?:
	var head: Node? = none
	var i = 1
	while i <= count:
		head = Node(value: i, next: head)
		i += 1
	return head

// Each walk advances an owning cursor with `get()` and a field move at the last use. A copy of
// the rest of the list per step makes it quadratic, so 100000 nodes would not finish.
fn sum_bound(head: Node?) Int:
	var total = 0
	var cur = head
	while cur.is_some():
		n := cur.get()
		total += n.value
		cur = n.next
	return total

fn sum_chained(head: Node?) Int:
	var total = 0
	var cur = head
	while cur.is_some():
		total += cur.get().value
		cur = cur.get().next
	return total

fn count_and_last(head: Node?) Int:
	var cur = head
	var last = 0
	while cur.is_some():
		n := cur.get()
		last = n.value
		cur = n.next
	return last

test "a cursor walk with a bound node moves along the list":
	expect_equal(sum_bound(build(100000)), 5000050000)?

test "a cursor walk through get and a field moves along the list":
	expect_equal(sum_chained(build(100000)), 5000050000)?

test "a walk over a short list and an empty list":
	expect_equal(count_and_last(build(3)), 1)?
	expect_equal(sum_bound(build(0)), 0)?
