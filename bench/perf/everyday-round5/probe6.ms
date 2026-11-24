import monotonic from "@std/time.ms"

enum Tree:
	Leaf(v Int)
	Node(l Tree, r Tree)

enum Cons:
	Nil
	Cell(head Int, tail Cons)

interface Shape:
	fn area() Int

type Sq:
	s Int

type Rc:
	w Int
	h Int

fn Sq.area() Int:
	return self.s * self.s

fn Rc.area() Int:
	return self.w * self.h

fn make(i Int) Shape:
	if i % 2 == 0: return Sq(i % 10)
	return Rc(i % 7, i % 5)

fn mk(depth Int, v Int) Tree:
	if depth == 0: return Tree.Leaf(v)
	return Tree.Node(mk(depth - 1, v * 2), mk(depth - 1, v * 2 + 1))

fn sum(t Tree) Int:
	match t:
		Leaf(v): return v
		Node(l, r): return (sum(l) + sum(r)) % 1000003

fn build_list(n Int) Cons:
	var c = Cons.Nil
	for i in 0..n:
		c = Cons.Cell(i, c)
	return c

fn total(c Cons) Int:
	var t = 0
	var cur = c

	while true:
		match cur:
			Nil: break
			Cell(h, rest):
				t += h
				cur = rest

	return t

fn stop(name String, t0 Int, chk Int) Void:
	now := monotonic().tick
	print(f"{name} {(now - t0) / 1000} {chk}")

fn q_tree() Int:
	var t = 0

	for r in 0..5:
		tree := mk(20, r + 1)
		t += sum(tree)

	return t

fn q_iface_alloc() Int:
	var t = 0

	for i in 0..10000000:
		s := make(i)
		t += s.area()

	return t

fn q_small_list_map() Int:
	var t = 0

	for i in 0..2000000:
		k := i % 5 + 1
		t += [i, i + 1, i + 2].map(fn v: v * k).sum()

	return t

fn q_closure_capture_list() Int:
	var fs List[fn(Int) Int] = []

	for i in 0..1000000:
		k := i % 9
		fs.append(fn v: v + k)

	var t = 0
	for r in 0..10:
		for f in fs:
			t += f(r)
	return t

fn q_cons() Int:
	c := build_list(1000000)
	return total(c)

fn run(name String, f fn() Int) Void:
	t0 := monotonic().tick
	c := f()
	stop(name, t0, c)

fn main() Void:
	run("q_tree", q_tree)
	run("q_iface_alloc", q_iface_alloc)
	run("q_small_list_map", q_small_list_map)
	run("q_closure_capture_list", q_closure_capture_list)
	run("q_cons", q_cons)
