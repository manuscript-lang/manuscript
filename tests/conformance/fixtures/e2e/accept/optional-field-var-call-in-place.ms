// conform: tags=testing,optional,mutation,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Node:
	key: Int
	left: Node?
	right: Node?

fn var Node.insert(key: Int) Void:
	if key < self.key:
		if self.left == null:
			self.left = Node(key, null, null)
			return

		self.left?.insert(key)
		return

	if self.right == null:
		self.right = Node(key, null, null)
		return

	self.right?.insert(key)

fn var Node.rename(delta: Int) Void:
	self.key += delta

fn count(node: Node?) Int:
	if node == null: return 0

	n := node
	return 1 + count(n.left) + count(n.right)

fn keys(var out: List[Int], node: Node?) Void:
	if node == null: return

	n := node
	keys(out, n.left)
	out.append(n.key)
	keys(out, n.right)

type Tag:
	label: String
	next: Tag?

fn var Tag.append_label(s: String) Void:
	self.label += s

fn var Node.rename_left(delta: Int) Void:
	self.left?.rename(delta)
	self.key += 1000

fn var Tag.label_next(s: String) Void:
	self.next?.append_label(s)

test "inserts through boxed optional fields":
	var root = Node(50, null, null)
	for k in [30, 70, 20, 40, 60, 80, 35, 45]:
		root.insert(k)

	var out: List[Int] = []
	keys(out, root)
	expect_equal(out, [20, 30, 35, 40, 45, 50, 60, 70, 80])?
	expect_equal(count(root), 9)?

test "an absent optional field is left alone":
	var root = Node(1, null, null)
	root.rename_left(5)
	expect_equal(root.left == null, true)?
	expect_equal(root.key, 1)?

test "a change through a present field is kept":
	var root = Node(10, Node(5, null, null), null)
	root.rename_left(100)
	expect_equal(root.left.get().key, 105)?
	expect_equal(root.key, 1010)?

test "owned payload fields are updated in place":
	var t = Tag("a", Tag("b", null))
	t.label_next("!")
	expect_equal(t.next.get().label, "b!")?
	expect_equal(t.label, "a")?
