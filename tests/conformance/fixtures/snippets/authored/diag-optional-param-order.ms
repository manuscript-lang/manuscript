// conform: tags=diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=agent-bug-bash
type Node:
	key: Int
	left: Node?

fn find(node: Node?, key: Int) Bool:
	return node.is_some() and key > 0
