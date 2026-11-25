// conform: tags=diagnostics,ownership,tier-core
// conform: phase=check
// conform: origin=design/proposals/argument-modes-in-signatures.md
type Command {
	name String
	kids List[Command]
}

fn hold Command.child(name String) &Command? {
	for kid in self.kids {
		if kid.name == name { return kid }
	}
	return null
}

fn node_at(hold node Command, path List[String], from Int) Command? {
	if from >= path.length() { return node }
	next := node.child(path[from])
	if next != null { return node_at(next, path, from + 1) }
	return null
}
