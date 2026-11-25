// conform: tags=diagnostics,scope-cleanup,tier-core
// conform: phase=check
// conform: origin=agent-bug-bash
fn lap(x Int) Int {
	return x + 1
}

fn main() Void {
	var t = 0
	t = lap(t)
	print("done")
}
// expect-error: MS3000 9:9 local binding t is never read: it is only read to compute its own next value, so nothing observes it; remove it, use it elsewhere, or name it with a leading '_' to ignore it
