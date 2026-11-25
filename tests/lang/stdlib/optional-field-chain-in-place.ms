// conform: tags=testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// `self.child?.change()` changes the child where it lies: an absent child ends the call, a present one is changed
// through every level, and a method that rewrites its own fields changes the child.

type Node {
	key Int
	left, right Node?
}

fn var Node.insert(key Int) Void {
	if key == self.key { return }
	if key < self.key {
		if self.left == null {
			self.left = Node(key, null, null)
			return
		}
		self.left?.insert(key)
		return
	}
	if self.right == null {
		self.right = Node(key, null, null)
		return
	}
	self.right?.insert(key)
}

fn Node.count() Int {
	var total = 1
	left := self.left
	if left != null { total += left.count() }
	right := self.right
	if right != null { total += right.count() }
	return total
}


fn var Node.reset(key Int) Void {
	self.key = key
	self.left = null
	self.right = null
}

fn var Node.reset_left(key Int) Void {
	self.left?.reset(key)
}

test "insert through optional children" {
	var root = Node(50, null, null)
	for key in [20, 70, 10, 30, 60, 80, 20, 70, 65] {
		root.insert(key)
	}
	expect_equal(root.count(), 8)?
}

test "a method that clears a child's own children" {
	var root = Node(5, Node(3, Node(1, null, null), null), null)
	root.reset_left(9)
	expect_equal(root.count(), 2)?
	var lone = Node(1, null, null)
	lone.reset_left(2)
	expect_equal(lone.count(), 1)?
}
