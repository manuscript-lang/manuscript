// Allocation-heavy object graphs: a binary search tree of boxed nodes, binary-tree
// churn, and a linked list.
type Node:
	key: Int
	left: Node?
	right: Node?

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn var Node.insert(key: Int) Unit:
	if key == self.key: return

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

fn Node.count() Int:
	var t = 1
	if l := self.left: t += l.count()
	if r := self.right: t += r.count()
	return t

fn Node.height() Int:
	var lh = 0
	var rh = 0
	if l := self.left: lh = l.height()
	if r := self.right: rh = r.height()
	return 1 + (if lh > rh: lh else: rh)

fn Node.sum() Int:
	var t = self.key
	if l := self.left: t += l.sum()
	if r := self.right: t += r.sum()
	return t

enum Tree:
	Leaf
	Branch(left: Tree, right: Tree)

fn make(depth: Int) Tree:
	if depth == 0: return Tree.Leaf
	return Tree.Branch(make(depth - 1), make(depth - 1))

fn count(t: Tree) Int:
	match t:
		Leaf: return 1
		Branch(l, r): return 1 + count(l) + count(r)

type Link:
	value: Int
	next: Link?

fn sum(l: Link?) Int:
	if x := l: return x.value + sum(x.next)
	return 0

fn main() Unit:
	var root = Node(1000000000, none, none)
	var x = 11

	for i in 0..400000:
		x = lcg(x)
		root.insert(x % 2000000000)

	print("bst {root.count()} {root.height()} {root.sum() % 1000003}")

	var nodes = 0
	for round in 0..40:
		nodes += count(make(16))
	print("trees {nodes}")

	var head: Link? = none
	for i in 0..1000000:
		head = Link(i, head)
	print("list {sum(head)}")
