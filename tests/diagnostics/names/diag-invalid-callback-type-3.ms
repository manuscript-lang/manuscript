// conform: tags=diagnostics,closures,generics,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn broken(handler fn(Missing) Int) Int => 1

fn apply[T, U](callback fn(T) U) Void => return

fn exercise() Void {
	apply(broken)
}
// expect-error: MS2001 4:22 unknown type Missing; declare it with 'type Missing:' / 'enum Missing:' / 'interface Missing:', declare it as a type parameter, or import it
