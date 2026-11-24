// conform: tags=scope-cleanup,diagnostics,tier-core
// conform: phase=check
type Gate:
	name String

fn move Gate.close() Void!:
	return ok()

fn main() Void!:
	gate := Gate("a")
	gate.close()?
	print(gate.name)
