import arguments from "@std/os/env.ms"

type Entry:
	priority: Int
	order: Int

fn before(a: Entry, b: Entry) Bool:
	return a.priority < b.priority or (a.priority == b.priority and a.order < b.order)

// Hole-based sift up, as in Rust's BinaryHeap::sift_up.
fn sift_up(var heap: List[Entry], start: Int, pos: Int) Unit:
	var at = pos
	hole := heap[at].clone()

	while at > start:
		parent := (at - 1) / 2
		if not before(hole, heap[parent]): break

		heap[at] = heap[parent].clone()
		at = parent

	heap[at] = hole

// Rust's sift_down_to_bottom followed by sift_up.
fn sift_down_to_bottom(var heap: List[Entry], pos: Int) Unit:
	end := heap.length()
	var at = pos
	hole := heap[at].clone()
	var child = 2 * at + 1

	while child <= end - 2:
		if not before(heap[child], heap[child + 1]): child += 1
		heap[at] = heap[child].clone()
		at = child
		child = 2 * at + 1

	if child == end - 1:
		heap[at] = heap[child].clone()
		at = child

	heap[at] = hole
	sift_up(var heap, pos, at)

fn main() Unit:
	n := arguments()[0].parse_int().get()
	var values: List[Int] = []
	var random = 1

	for i in 0..n:
		random = (random * 1103515245 + 12345) % 2147483648
		values.append(random % 100003)

	var heap: List[Entry] = []

	for i in 0..n:
		heap.append(Entry(priority: values[i], order: i))
		sift_up(var heap, 0, heap.length() - 1)

	var sum = 0

	for i in 0..n:
		var top = heap.pop().get()

		if not heap.is_empty():
			swapped := heap[0].clone()
			heap[0] = top
			top = swapped
			sift_down_to_bottom(var heap, 0)

		sum += (top.priority + 1) * (i + 1)

	print("{sum}")
