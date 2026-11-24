// conform: tags=scope-cleanup,diagnostics,tier-core
// conform: phase=check
type Gate {
	name String
}

fn move Gate.close() Void! {
	return ok()
}

fn shut(var gate Gate) Void! {
	return gate.close()
}
