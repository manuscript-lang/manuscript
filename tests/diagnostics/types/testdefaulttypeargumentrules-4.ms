// conform: tags=diagnostics,formatter,generics,interfaces,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/default_type_arguments_test.go:26 TestDefaultTypeArgumentRules
interface Named {
	fn name() String
}

fn f[T Named = Int]() Void => void
// expect-error: MS3000 8:16 Int does not satisfy Named; choose a default that already implements it
