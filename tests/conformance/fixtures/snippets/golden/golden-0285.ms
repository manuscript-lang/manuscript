// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
	s := SetBuilder[String]()
	return 0
}
// expect-error: MS2001 4:10 unknown binding SetBuilder; declare it with 'SetBuilder := ...' before use, define 'fn SetBuilder(...) T { ... }', or import it from a module
