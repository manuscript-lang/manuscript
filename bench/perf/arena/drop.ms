import (
	Arena, Id from "@std/collections/arena.ms",
	monotonic, Instant from "@std/time.ms",
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

fn build_b(rounds: Int) List[Tree]:
	var keep: List[Tree] = []
	for _i in 0..rounds:
		keep.append(make(16))
	return keep

fn build_a(rounds: Int) List[Arena[ANode]]:
	var keep: List[Arena[ANode]] = []

	for _i in 0..rounds:
		var a = Arena[ANode]()
		_root := amake(var a, 16)
		keep.append(a)

	return keep

fn us(t0: Instant) Int:
	return monotonic().difference(t0).to_nanoseconds() / 1000

fn main() Unit:
	for _r in 0..4:
		b := build_b(20)
		a := build_a(20)
		t0 := monotonic()
		nb := b.length()
		tb := us(t0)
		t1 := monotonic()
		na := a.length()
		ta := us(t1)
		print("{nb} {na} drop boxed {tb} us, drop arena {ta} us")
