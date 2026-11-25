// conform: tags=diagnostics
// conform: phase=check
fn affine(n Int) Result[Int, Cause] {
	if n < 0 { return ok(9223372036854775807) }
	return ok(n + 1)
}
// expect-error: MS2001 3:30 unknown type Cause; declare it with 'type Cause:' / 'enum Cause:' / 'interface Cause:', declare it as a type parameter, or import it
