import (
	BitSet from "@std/collections/bitset.ms",
	Deque from "@std/collections/deque.ms",
	PriorityQueue, Queue from "@std/collections/queue.ms",
	SortedMap from "@std/collections/sorted.ms",
)

// Queue, PriorityQueue, Deque, BitSet and SortedMap at two sizes each, so ns/op staying
// flat shows the complexity class.
bench "queue.enqueue_dequeue_100000" per 200000:
	var queue = Queue[Int]()
	for i in 0..100000:
		queue.enqueue(i)

	var total = 0
	for i in 0..100000:
		total += queue.dequeue() or 0
	total

bench "priority_queue.enqueue_dequeue_100000" per 200000:
	var queue = PriorityQueue[Int]()
	for i in 0..100000:
		queue.enqueue((i * 7919) % 100003)

	var total = 0
	for i in 0..100000:
		total += queue.dequeue() or 0
	total

bench "deque.push_pop_both_ends_100000" per 400000:
	var deque = Deque[Int]()

	for i in 0..100000:
		deque.push_back(i)
		deque.push_front(i)

	var total = 0
	for i in 0..100000:
		total += (deque.pop_front() or 0) + (deque.pop_back() or 0)
	total

bench "bitset.add_contains_100000" per 200000:
	var set = BitSet()
	for i in 0..100000:
		set.add((i * 7919) % 1000003)?

	var hits = 0
	for i in 0..100000:
		if set.contains(i):
			hits += 1
	hits + set.length()

bench "sorted_map.add_contains_100000" per 200000:
	var map = SortedMap[Int, Int]()
	var x = 1

	for i in 0..100000:
		x = (x * 1103515245 + 12345) % 2147483648
		map.add(x, i)

	var hits = 0

	for i in 0..100000:
		x = (x * 1103515245 + 12345) % 2147483648
		if map.contains(x):
			hits += 1

	hits + map.length()

bench "list.insert_remove_middle_100000" per 2000:
	var list = 0..100000

	for i in 0..1000:
		list.insert(100000 / 2, i)
		list.remove(100000 / 2)

	list.length()

bench "queue.enqueue_dequeue_400000" per 800000:
	var queue = Queue[Int]()
	for i in 0..400000:
		queue.enqueue(i)

	var total = 0
	for i in 0..400000:
		total += queue.dequeue() or 0
	total

bench "priority_queue.enqueue_dequeue_400000" per 800000:
	var queue = PriorityQueue[Int]()
	for i in 0..400000:
		queue.enqueue((i * 7919) % 100003)

	var total = 0
	for i in 0..400000:
		total += queue.dequeue() or 0
	total

bench "deque.push_pop_both_ends_400000" per 1600000:
	var deque = Deque[Int]()

	for i in 0..400000:
		deque.push_back(i)
		deque.push_front(i)

	var total = 0
	for i in 0..400000:
		total += (deque.pop_front() or 0) + (deque.pop_back() or 0)
	total

bench "bitset.add_contains_400000" per 800000:
	var set = BitSet()
	for i in 0..400000:
		set.add((i * 7919) % 1000003)?

	var hits = 0
	for i in 0..400000:
		if set.contains(i):
			hits += 1
	hits + set.length()

bench "sorted_map.add_contains_400000" per 800000:
	var map = SortedMap[Int, Int]()
	var x = 1

	for i in 0..400000:
		x = (x * 1103515245 + 12345) % 2147483648
		map.add(x, i)

	var hits = 0

	for i in 0..400000:
		x = (x * 1103515245 + 12345) % 2147483648
		if map.contains(x):
			hits += 1

	hits + map.length()

bench "list.insert_remove_middle_400000" per 2000:
	var list = 0..400000

	for i in 0..1000:
		list.insert(400000 / 2, i)
		list.remove(400000 / 2)

	list.length()
