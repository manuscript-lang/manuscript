import (
	Deque from "@std/collections/deque.ms",
	PriorityQueue, Queue from "@std/collections/queue.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

// `for item in container` over an `Iterable` container borrows each item: the lambdas below are
// never cloned.
test "deque iterates front to back by borrow":
	var d = Deque[Int]()
	d.push_back(2)
	d.push_back(3)
	d.push_front(1)

	var seen: List[Int] = []
	for item in d:
		seen.append(item)
	expect_equal(seen, [1, 2, 3])?
	expect_equal(d.length(), 3)?

test "queue iterates oldest first and skips consumed slots":
	var q = Queue[String]()
	q.enqueue("a")
	q.enqueue("b")
	q.enqueue("c")
	expect_equal(q.dequeue(), "a")?

	var seen: List[String] = []
	for item in q:
		seen.append(item.clone())
	expect_equal(seen, ["b", "c"])?

test "priority queue iterates every value and peek borrows":
	var q = PriorityQueue[Int]()
	q.enqueue(5)
	q.enqueue(1)
	q.enqueue(3)

	var total = 0
	for item in q:
		total += item
	expect_equal(total, 9)?
	expect_equal(q.peek(), 1)?

test "break and continue work in a borrowing loop":
	var d = Deque[Int]()
	for i in 0..6:
		d.push_back(i)

	var seen: List[Int] = []

	for item in d:
		if item == 1: continue
		if item == 4: break

		seen.append(item)

	expect_equal(seen, [0, 2, 3])?

test "empty container and temporary iterable":
	var d = Deque[Int]()
	var count = 0
	for item in d:
		count += item + 1
	expect_equal(count, 0)?
	for item in Deque[Int]():
		count += 1
	expect_equal(count, 0)?

test "nested loops over one container":
	var d = Deque[Int]()
	d.push_back(1)
	d.push_back(2)

	var pairs = 0
	for a in d:
		for b in d:
			pairs += a * b
	expect_equal(pairs, 9)?

test "callbacks are called through the borrow":
	var d = Deque[fn(Int) Int]()
	d.push_back(fn(x: Int) Int: return x + 1)
	d.push_back(fn(x: Int) Int: return x * 10)

	var total = 0
	for f in d:
		total += f(2)
	expect_equal(total, 23)?
