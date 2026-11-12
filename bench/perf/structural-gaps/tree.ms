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

fn main() Unit:
	var root = Node(500000, none, none)
	var x = 12345
	for i in 0..200000:
		x = (x * 1103515245 + 12345) % 2147483648
		root.insert(x % 1000000)
	print(depth(root))
