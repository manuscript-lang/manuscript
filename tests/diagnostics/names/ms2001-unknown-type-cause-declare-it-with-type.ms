// conform: tags=diagnostics
// conform: phase=check
fn affine(n Int = 0) Result[Int, Cause] {
	if n < 0 { return error(Cause("negative")) }
	return ok(n + 1)
}
// expect-error: MS2001 3:34 unknown type Cause; declare it with 'type Cause:' / 'enum Cause:' / 'interface Cause:', declare it as a type parameter, or import it
// expect-error: MS2001 4:29 unknown binding Cause; declare it with 'Cause := ...' before use, define 'fn Cause(...) T { ... }', or import it from a module
