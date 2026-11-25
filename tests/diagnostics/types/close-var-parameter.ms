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
// expect-error: MS3000 12:12 cannot move `gate` out of the function: the caller keeps ownership of a var parameter and closes it; a resource cannot be cloned, so change it in place
