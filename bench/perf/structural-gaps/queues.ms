import (
	Deque from "@std/collections/deque.ms",
	PriorityQueue from "@std/collections/queue.ms",
)

fn bfs(w: Int, h: Int) Int:
	var seen = [false].repeated(w * h)
	var dist = [0].repeated(w * h)
	var q = Deque[Int]()
	q.push_back(0)
	seen[0] = true

	var far = 0

	while true:
		at := q.pop_front()
		if at.is_none(): break

		p := at.get()
		x := p % w
		y := p / w
		far = dist[p]

		if x + 1 < w and not seen[p + 1] and (x * 7 + y * 13) % 11 != 0:
			seen[p + 1] = true
			dist[p + 1] = dist[p] + 1
			q.push_back(p + 1)

		if y + 1 < h and not seen[p + w]:
			seen[p + w] = true
			dist[p + w] = dist[p] + 1
			q.push_back(p + w)

		if x > 0 and not seen[p - 1] and (x * 5 + y * 3) % 7 != 0:
			seen[p - 1] = true
			dist[p - 1] = dist[p] + 1
			q.push_back(p - 1)

	return far

fn heap(n: Int) Int:
	var pq = PriorityQueue[Int]()
	var seed = 12345
	var s = 0

	for i in 0..n:
		seed = (seed * 1103515245 + 12345) % 2147483648
		pq.enqueue(seed % 100000)
		if i % 3 == 2:
			s += pq.dequeue().get(0)

	return s

fn main() Unit:
	print("{bfs(1500, 1500)} {heap(2000000)}")
