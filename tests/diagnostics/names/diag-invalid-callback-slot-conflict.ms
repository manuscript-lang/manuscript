// conform: tags=diagnostics,closures,generics,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn broken(first Missing, second Int) Int => 1

fn apply[T](callback fn(T, String) Int) Void => return

fn exercise() Void {
	apply(broken)
}
// expect-error: MS2001 4:17 unknown type Missing; declare it with 'type Missing:' / 'enum Missing:' / 'interface Missing:', declare it as a type parameter, or import it
// expect-error: MS3080 9:11 conflicting generic inference; arguments imply different types for one type parameter, so make them the same type or give type arguments explicitly, e.g. f[Int](...)
