// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	PriorityQueue, Queue from "@std/collections/queue.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

test "FIFO capacity empty reads draining and reuse":
	var queue = Queue[Int](2)
	expect_false(not queue.is_empty() or queue.peek().is_some())?
	expect_false((not queue.enqueue(1) or not queue.enqueue(2) or queue.enqueue(3)))?
	expect_false(queue.peek() != 1 or queue.length() != 2)?
	expect_false(queue.dequeue() != 1 or queue.dequeue() != 2)?
	expect_false(queue.dequeue().is_some() or not queue.enqueue(4))?

test "priority queue orders values and honors capacity":
	var queue = PriorityQueue[Int](3)
	queue.enqueue(3)
	queue.enqueue(1)
	queue.enqueue(2)
	expect_false(queue.enqueue(0))?
	expect_equal(queue.peek(), 1)?
	for expected in [1, 2, 3]:
		expect_equal(queue.dequeue(), expected)?
	expect_false(not queue.is_empty())?

test "priority queue sorts many values and copies are independent":
	var queue = PriorityQueue[Int]()
	for index in 0..200:
		queue.enqueue((index * 37) % 101)

	var copy = queue.clone()
	expect_equal(copy.dequeue(), 0)?
	expect_equal(queue.length(), 200)?

	var previous = -1

	while not queue.is_empty():
		next := queue.dequeue().get()
		expect_false(next < previous)?
		previous = next

	expect_equal(copy.length(), 199)?

test "ordered priority queue defaults to natural order and honors capacity":
	var queue = PriorityQueue[String](capacity: 2)
	expect_true(queue.enqueue("b"))?
	expect_true(queue.enqueue("a"))?
	expect_false(queue.enqueue("c"))?
	expect_equal(queue.dequeue(), "a")?
	expect_equal(queue.dequeue(), "b")?
	expect_equal(queue.dequeue(), none)?
