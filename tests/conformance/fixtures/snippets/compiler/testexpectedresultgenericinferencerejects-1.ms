// conform: tags=control-flow,diagnostics,formatter,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/contextual_generics_test.go:80 TestExpectedResultGenericInferenceRejects
interface Read {
	fn get() Int
}

type Box {
	value Int
}

fn Box.get() Int => self.value

fn first() Read => identity(Box(1))
// expect-error: MS2001 14:20 unknown binding identity; declare it with 'identity := ...' before use, define 'fn identity(...) T { ... }', or import it from a module
