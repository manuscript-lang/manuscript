// conform: tags=testing,tier-io
// conform: phase=test
import (
	Deque from "@std/collections/deque.ms",
	Closeable, panic from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_fault from "@std/test/test.ms",
)

// A body fault closes a collection of resources while unwinding. A close that fails
// there faults again, and the cleanup that owns the collection must still free every
// part exactly
// once: the optional that holds the failing resource is whole again when the fault starts.
type Item:
	id: Int
	log: String
	fail: Bool

fn move Item.close() Void!:
	append_file(self.log, f"{self.id},").wait()?
	if self.fail: return error(Error("close failed"))

fn events(log: String) String!:
	bytes := read_file(log).wait()?
	return ok(bytes.decode_utf8() or "")

fn deque_then_fault(log: String) Void:
	var queue = Deque[Item]()
	queue.push_back(Item(1, log.clone(), true))
	queue.push_back(Item(2, log.clone(), false))
	panic("body fault")

fn list_then_fault(move log: String) Void:
	var items: List[Item?] = [
		Item(1, log.clone(), true),
		null,
		Item(2, log.clone(), false),
	]
	panic("body fault")
	void items.length()

test "a failed close of a deque element while unwinding keeps the body fault":
	temp := temporary("failed-close-")?
	log := f"{temp.path()}/log"
	message := expect_fault(fn: deque_then_fault(log.clone()))?
	expect_equal(message, "body fault")?
	expect_equal(events(log)?, "2,1,")?

test "a failed close of an optional element while unwinding keeps the body fault":
	temp := temporary("failed-close-")?
	log := f"{temp.path()}/log"
	message := expect_fault(fn: list_then_fault(log.clone()))?
	expect_equal(message, "body fault")?
	expect_equal(events(log)?, "2,1,")?
