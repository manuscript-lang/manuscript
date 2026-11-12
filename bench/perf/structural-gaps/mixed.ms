import Promise, promise, wait_all from "@std/concurrency/promise.ms"

fn case_a() Int:
	n := 100000
	var xs: List[Float] = []
	var ys: List[Float] = []

	for i in 0..n:
		xs.append(i.to_float() * 0.5)
		ys.append(1.0)

	var s = 0.0

	for r in 0..300:
		for i in 0..n:
			ys[i] = ys[i] * 0.999 + xs[i] * 0.001
		for i in 0..n:
			s += ys[i]

	return s.truncate_to_int().get(0) % 1000003

type Rec:
	id: Int
	score: Int
	name: String

fn case_b() Int:
	var t = 0

	for r in 0..5:
		var rs: List[Rec] = []
		for i in 0..200000:
			rs.append(Rec(i, (i * 7919 + r) % 100003, "n{i % 1000}"))
		rs.sort(fn a, b: a.score - b.score)
		t += rs[1000].id

	return t

type Node:
	key: Int
	left: Node?
	right: Node?

fn var Node.insert(key: Int) Unit:
	if key < self.key:
		if self.left.is_none():
			self.left = Node(key, none, none)
			return

		self.left?.insert(key)
		return

	if self.right.is_none():
		self.right = Node(key, none, none)
		return

	self.right?.insert(key)

fn depth(node: Node?) Int:
	if node.is_none(): return 0

	n := node.get()
	return 1 + depth(n.left).max(depth(n.right))

fn case_c() Int:
	var root = Node(500000, none, none)
	var x = 12345

	for i in 0..200000:
		x = (x * 1103515245 + 12345) % 2147483648
		root.insert(x % 1000000)

	return depth(root)

fn work(i: Int) Int!:
	var s = 0
	for k in 0..200:
		s += (i + k) % 7
	return ok(s)

fn case_d() Int:
	var t = 0

	for r in 0..20:
		var ps: List[Promise[Int]] = []
		for i in 0..5000:
			ps.append(promise[Int](fn: work(i)))
		for v in wait_all(ps).get():
			t += v

	return t

fn case_e() Int:
	var words: List[String] = []
	for i in 0..200000:
		words.append("w{i * 7919 % 5003}")

	var t = 0

	for r in 0..20:
		for w in words:
			if w == "w42" or w.starts_with("w49"): t += 1
			t += w.length()

	return t

fn case_f() Int:
	var xs: List[Int] = []
	for i in 0..1000000:
		xs.append(i * 7919 % 10007)

	var t = 0

	for r in 0..20:
		t += xs.filter(fn v: v % 3 == 0).length()
		t += xs.map(fn v: v + r).fold(0, fn(a: Int, v: Int) Int: (a + v) % 1000003)
		if xs.contains(-r - 1): t += 1
		t += xs.index_of(10006 - r).get(0)

	return t

fn main() Unit:
	print("{case_a()} {case_b()} {case_c()} {case_d()} {case_e()} {case_f()}")
