// conform: tags=diagnostics,scope-cleanup,tier-core
// conform: phase=check
// conform: origin=agent-bug-bash
fn lap(x Int) Int:
	return x + 1

fn main() Void:
	var t = 0
	t = lap(t)
	print("done")
