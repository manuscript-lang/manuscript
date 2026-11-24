// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// A type that holds itself through a list closes every resource in the tree once, each node after its children.
type Res:
	id Int

fn move Res.close() Void!:
	print(f"close {self.id}")

type Node:
	kids List[Node]
	val Res?

fn leaf(id Int) Node:
	return Node(val: Res(id), kids: [])

export fn main() Int:
	root := Node(val: Res(1), kids: [leaf(2), Node(val: null, kids: [leaf(3), leaf(4)])])
	print(f"kids {root.kids.length()}")
	return 0
