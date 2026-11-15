// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// A type that holds itself through a list closes every resource in the tree once, each node after its children.
type Res:
	id: Int

fn var Res.close() Void!:
	print(f"close {self.id}")

type Node:
	val: Res?
	kids: List[Node]

fn leaf(id: Int) Node:
	return Node(Res(id), [])

export fn main() Int:
	root := Node(Res(1), [leaf(2), Node(none, [leaf(3), leaf(4)])])
	print(f"kids {root.kids.length()}")
	return 0
