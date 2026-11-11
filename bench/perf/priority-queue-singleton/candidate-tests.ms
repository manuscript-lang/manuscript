import (
	PriorityQueue from "@std/collections/queue.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

type Job:
	priority: Int
	id: Int

fn Job.compare(other: Job) Int:
	return self.priority.compare(other.priority)

test "singleton dequeue leaves a bounded queue ready for reuse":
	var queue = PriorityQueue[Int](capacity: 1)

	for value in [-7, 0, 9, -1]:
		expect_true(queue.enqueue(value))?
		expect_false(queue.enqueue(100))?
		expect_equal(queue.dequeue().get(), value)?
		expect_equal(queue.length(), 0)?
		expect_true(queue.is_empty())?
		expect_true(queue.peek().is_none())?
		expect_true(queue.dequeue().is_none())?

test "singleton fast path composes with larger stable heaps":
	var queue = PriorityQueue[Job]()
	queue.enqueue(Job(0, -1))
	expect_equal(queue.dequeue().get().id, -1)?
	queue.enqueue(Job(2, 0))
	queue.enqueue(Job(1, 1))
	queue.enqueue(Job(1, 2))
	queue.enqueue(Job(2, 3))
	for id in [1, 2, 0, 3]:
		expect_equal(queue.dequeue().get().id, id)?
	expect_true(queue.is_empty())?
	queue.enqueue(Job(1, 4))
	expect_equal(queue.dequeue().get().id, 4)?
	expect_true(queue.dequeue().is_none())?
