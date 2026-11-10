import (
	Arena, Id from "@std/collections/arena.ms",
	monotonic from "@std/time.ms",
)

// Boxed: one allocation per node.
enum Tree:
	Leaf
	Node(left: Tree, right: Tree)

fn make(depth: Int) Tree:
	if depth == 0: return Leaf

	return Node(make(depth - 1), make(depth - 1))

fn check(t: Tree) Int:
	match t:
		Leaf:
			return 1
		Node(l, r):
			return 1 + check(l) + check(r)

// Arena: nodes in one flat list, links are handles.
type ANode:
	left: Id[ANode]?
	right: Id[ANode]?

fn amake(var a: Arena[ANode], depth: Int) Id[ANode]:
	if depth == 0: return a.add(ANode(left: none, right: none))

	l := amake(var a, depth - 1)
	r := amake(var a, depth - 1)
	return a.add(ANode(left: l, right: r))

fn acheck(a: Arena[ANode], id: Id[ANode]) Int:
	n := a.get(id).get()
	var total = 1
	if l := n.left:
		total += acheck(a, l)
	if r := n.right:
		total += acheck(a, r)
	return total

// Churn: keep a window of live records, add one and remove the oldest.
type Rec:
	key: Int
	val: Int

fn churn_map(n: Int, window: Int) Int:
	var m: Map[Int, Rec] = Map[Int, Rec]()
	var sum = 0

	for i in 0..n:
		m.add(i, Rec(key: i, val: i * 2))

		if i >= window:
			if r := m.get(i - window):
				sum += r.val
			m.remove(i - window)

	return sum

fn churn_arena(n: Int, window: Int) Int:
	var a = Arena[Rec]()
	var ids: List[Id[Rec]] = []
	var sum = 0

	for i in 0..n:
		ids.append(a.add(Rec(key: i, val: i * 2)))
		if i >= window:
			if r := a.remove(ids.get(i - window)):
				sum += r.val

	return sum

fn timed(name: String, f: fn() Int) Unit:
	t0 := monotonic()
	r := f()
	print(
		"{name} {monotonic().difference(t0).to_nanoseconds() / 1000000} ms result {r}"
	)

fn tree_boxed() Int:
	var t = 0
	for _i in 0..20:
		t += check(make(16))
	return t

fn tree_arena() Int:
	var t = 0

	for _i in 0..20:
		var a = Arena[ANode]()
		root := amake(var a, 16)
		t += acheck(a, root)

	return t

fn main() Unit:
	timed("tree_boxed_d16_x20", tree_boxed)
	timed("tree_arena_d16_x20", tree_arena)
	timed("churn_map_2M_w1000", fn() Int: return churn_map(2000000, 1000))
	timed("churn_arena_2M_w1000", fn() Int: return churn_arena(2000000, 1000))
