// Random graph: adjacency lists, BFS, Dijkstra with a priority queue, union-find.
import (
	Deque from "@std/collections/deque.ms",
	PriorityQueue from "@std/collections/queue.ms",
)

type Edge:
	to: Int
	w: Int

type Item:
	dist: Int
	node: Int

fn Item.compare(other: Item) Int:
	if self.dist != other.dist: return self.dist - other.dist
	return self.node - other.node

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn build(n: Int, m: Int) List[List[Edge]]:
	var adj: List[List[Edge]] = []
	for i in 0..n:
		adj.append([])

	var x = 7

	for i in 0..m:
		x = lcg(x)

		a := x % n
		x = lcg(x)

		b := x % n
		x = lcg(x)

		w := 1 + x % 100
		adj[a].append(Edge(b, w))
		adj[b].append(Edge(a, w))

	return adj

fn bfs(adj: List[List[Edge]], start: Int) Int:
	var level = List[Int]()
	for i in 0..adj.length():
		level.append(-1)

	var queue = Deque[Int]()
	level[start] = 0
	queue.push_back(start)

	var reached = 0
	var depth_sum = 0

	while true:
		next := queue.pop_front()
		if next.is_none(): break

		u := next.get()
		reached += 1
		depth_sum += level[u]

		for e in adj[u]:
			if level[e.to] < 0:
				level[e.to] = level[u] + 1
				queue.push_back(e.to)

	return reached * 1000 + depth_sum % 1000

fn dijkstra(adj: List[List[Edge]], start: Int) Int:
	var dist = List[Int]()
	for i in 0..adj.length():
		dist.append(1000000000)

	var pq = PriorityQueue[Item]()
	dist[start] = 0
	pq.enqueue(Item(0, start))

	while true:
		next := pq.dequeue()
		if next.is_none(): break

		it := next.get()
		if it.dist > dist[it.node]: continue

		for e in adj[it.node]:
			nd := it.dist + e.w

			if nd < dist[e.to]:
				dist[e.to] = nd
				pq.enqueue(Item(nd, e.to))

	var total = 0
	var far = 0

	for d in dist:
		if d < 1000000000:
			total += d
			if d > far: far = d

	return total % 1000003 * 1000 + far

fn find(parent: List[Int], x: Int) Int:
	var r = x
	while parent[r] != r:
		r = parent[r]
	return r

fn components(n: Int, m: Int) Int:
	var parent = List[Int]()
	for i in 0..n:
		parent.append(i)

	var x = 99
	var count = n

	for i in 0..m:
		x = lcg(x)

		a := find(parent, x % n)
		x = lcg(x)

		b := find(parent, x % n)

		if a != b:
			parent[a] = b
			count -= 1

	return count

fn main() Unit:
	n := 200000
	adj := build(n, 800000)
	print("bfs {bfs(adj, 0)}")
	print("dijkstra {dijkstra(adj, 0)}")
	print("components {components(n, 150000)}")
