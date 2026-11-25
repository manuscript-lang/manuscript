// conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:546 TestImplementationDeclarationParameters
interface Read[V] {
	fn get() V
}

type Box[T] {
	value T
}

fn Box[U].get() U {
	return self.value
}
// expect-error: MS2001 12:17 unknown type U; declare it with 'type U:' / 'enum U:' / 'interface U:', declare it as a type parameter, or import it
// expect-error: MS2001 12:8 unknown type U; declare it with 'type U:' / 'enum U:' / 'interface U:', declare it as a type parameter, or import it
