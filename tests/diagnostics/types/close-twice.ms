// conform: tags=scope-cleanup,diagnostics,tier-core
// conform: phase=check
type Gate {
	name String
}

fn move Gate.close() Void! {
	return ok()
}

fn main() Void! {
	gate := Gate("a")
	gate.close()?
	gate.close()?
}
// expect-error: MS3000 13:5 `gate` is moved here but used again at 14:5; a resource has one owner and cannot be cloned, so move it only at its last use, or pass it where it is only read
