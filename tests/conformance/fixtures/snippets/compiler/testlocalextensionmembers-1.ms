// conform: tags=diagnostics,faults,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/local_extensions_test.go:138 TestLocalExtensionMembers
export fn read(value Box[Int]) Int {
	return value.get()
}
// expect-error: MS2001 4:22 unknown type Box; declare it with 'type Box:' / 'enum Box:' / 'interface Box:', declare it as a type parameter, or import it
