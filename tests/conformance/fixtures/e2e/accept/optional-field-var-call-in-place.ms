// conform: tags=testing,optional,mutation,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

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

fn var Node.rename(delta: Int) Unit:
	self.key += delta

fn count(node: Node?) Int:
	if node.is_none(): return 0

	n := node.get()
	return 1 + count(n.left) + count(n.right)

fn keys(node: Node?, var out: List[Int]) Unit:
	if node.is_none(): return

	n := node.get()
	keys(n.left, var out)
	out.append(n.key)
	keys(n.right, var out)

type Tag:
	label: String
	next: Tag?

fn var Tag.append_label(s: String) Unit:
	self.label += s

test "inserts through boxed optional fields":
	var root = Node(50, none, none)
	for k in [30, 70, 20, 40, 60, 80, 35, 45]:
		root.insert(k)

	var out: List[Int] = []
	keys(root, var out)
	expect_equal(out, [20, 30, 35, 40, 45, 50, 60, 70, 80])?
	expect_equal(count(root), 9)?

test "an absent optional field is left alone":
	var root = Node(1, none, none)
	root.left?.rename(5)
	expect_equal(root.left.is_none(), true)?
	expect_equal(root.key, 1)?

test "a change through a present field is kept":
	var root = Node(10, Node(5, none, none), none)
	root.left?.rename(100)
	expect_equal(root.left.get().key, 105)?
	expect_equal(root.key, 10)?

test "owned payload fields are updated in place":
	var t = Tag("a", Tag("b", none))
	t.next?.append_label("!")
	expect_equal(t.next.get().label, "b!")?
	expect_equal(t.label, "a")?
