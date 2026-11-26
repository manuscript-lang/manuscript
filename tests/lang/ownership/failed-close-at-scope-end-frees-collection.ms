// conform: tags=testing,tier-io
// conform: phase=test
import (
	Deque from "@std/collections/deque.ms",
	expect_contains, expect_fault from "@std/test/test.ms",
)

// A close that fails where its scope ends faults. The fault must still free the
// collection that held the failing resource: the buffer and the elements the close
// never reached.
type Item {
	id Int
	label String
}

fn move Item.close() Void! {
	return error(Error("close failed"))
}

fn deque_at_scope_end() Void {
	var queue = Deque[Item]()
	for id in 0..3 {
		queue.push_back(Item(id, f"item-{id}-with-a-label-long-enough-to-allocate"))
	}
}

fn list_at_scope_end() Void {
	var items = List[Item]()
	for id in 0..3 {
		items.append(Item(id, f"item-{id}-with-a-label-long-enough-to-allocate"))
	}
}

fn optionals_at_scope_end() Void {
	var items List[Item?] = []
	for id in 0..3 {
		items.append(Item(id, f"item-{id}-with-a-label-long-enough-to-allocate"))
	}
}

test "a failed close of a deque element at scope end faults" {
	message := expect_fault(() => deque_at_scope_end())?
	expect_contains(message, "could not be closed")?
}

test "a failed close of a list element at scope end faults" {
	message := expect_fault(() => list_at_scope_end())?
	expect_contains(message, "could not be closed")?
}

test "a failed close of an optional element at scope end faults" {
	message := expect_fault(() => optionals_at_scope_end())?
	expect_contains(message, "could not be closed")?
}
// expect-exit: 0
// expect-tests: passed=3 failed=0
