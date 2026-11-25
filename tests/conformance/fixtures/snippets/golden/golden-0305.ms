// conform: tags=diagnostics
// conform: phase=check
fn broken(value Missing) Void => return

fn empty[T]() T? => null

fn first() Void {
	value := empty()
}
// expect-error: MS2001 3:17 unknown type Missing; declare it with 'type Missing:' / 'enum Missing:' / 'interface Missing:', declare it as a type parameter, or import it
// expect-error: MS3080 8:14 cannot infer type argument T for empty; write empty[T](...) with an explicit type for T; call arguments and the expected result must determine every type parameter
