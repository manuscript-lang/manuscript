// conform: tags=diagnostics
// conform: phase=check
fn make_fixture() State {
	return State(1)
}

test "test" {
	return
}
// expect-error: MS2001 3:19 unknown type State; declare it with 'type State:' / 'enum State:' / 'interface State:', declare it as a type parameter, or import it
// expect-error: MS3000 3:1 make_fixture must return a concrete type implementing @std/test/test.ms TestHooks; return your fixture type and declare any of fn var Fixture.before_all(), before_each(), after_each() and after_all() with no arguments returning Void!
// expect-error: MS2001 4:12 unknown binding State; declare it with 'State := ...' before use, define 'fn State(...) T { ... }', or import it from a module
