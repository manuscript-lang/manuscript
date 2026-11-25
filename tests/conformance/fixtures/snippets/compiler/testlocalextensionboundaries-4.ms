// conform: tags=diagnostics,formatter,scope-cleanup,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/local_extensions_test.go:38 TestLocalExtensionBoundaries
fn use(value Box[Int]) Void {
	_resource := value
	return
}
// expect-error: MS2001 4:14 unknown type Box; declare it with 'type Box:' / 'enum Box:' / 'interface Box:', declare it as a type parameter, or import it
