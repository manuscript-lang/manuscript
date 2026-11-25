// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/local_extensions_test.go:31 TestLocalExtensionBoundaries
fn use(value Box[Int]) Read[Int] {
	return Read[Int](value: value)
}
// expect-error: MS2001 4:14 unknown type Box; declare it with 'type Box:' / 'enum Box:' / 'interface Box:', declare it as a type parameter, or import it
// expect-error: MS2001 4:24 unknown type Read; declare it with 'type Read:' / 'enum Read:' / 'interface Read:', declare it as a type parameter, or import it
// expect-error: MS2001 5:12 unknown binding Read; declare it with 'Read := ...' before use, define 'fn Read(...) T { ... }', or import it from a module
