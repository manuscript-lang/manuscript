import (
	Deque from "@std/collections/deque.ms",
	PriorityQueue, Queue from "@std/collections/queue.ms",
	arguments from "@std/os/env.ms",
	keep from "@std/test/bench.ms",
	monotonic from "@std/time.ms",
)

fn main() Unit:
	args := arguments()
	operation := args[0]
	size := args[1].parse_int().get()
	shape := args[2]
	repeats := args[3].parse_int().get()
	var values: List[Int] = []
	var random = 1

	for i in 0..size:
		random = (random * 1103515245 + 12345) % 2147483648

		value := if shape == "ascending": i else: (
			if shape == "descending": size - i else: (
				if shape == "duplicate": i % 7 else: random % 100003
			)
		)
		values.append(value)

	var checksum = 0
	var priority = PriorityQueue[Int]()
	var queue = Queue[Int]()
	var deque = Deque[Int]()
	started := monotonic()

	for unused in 0..repeats:
		if operation == "priority":
			for value in values:
				priority.enqueue(value)
			for i in 0..size:
				checksum += (priority.dequeue().get() + 1) * (i + 1)
		else if operation == "queue":
			for value in values:
				queue.enqueue(value)
			for i in 0..size:
				checksum += (queue.dequeue().get() + 1) * (i + 1)
		else:
			for i in 0..size:
				if i % 2 == 0:
					deque.push_front(values[i])
				else:
					deque.push_back(values[i])

			for i in 0..size:
				checksum += (deque.pop_front().get() + 1) * (i + 1)

		keep(checksum).get()

	elapsed := monotonic().difference(started).to_nanoseconds()
	print("{elapsed} {checksum}")
