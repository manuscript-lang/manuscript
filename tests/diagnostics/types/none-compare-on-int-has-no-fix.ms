// conform: tags=diagnostics,tier-core
// conform: phase=check
fn run(n Int) Bool {
	return n == null
}
// expect-error: MS3000 4:14 null has no type of its own here; compare a nullable with `x == null`, or compare plain values with each other, e.g. x == 3
