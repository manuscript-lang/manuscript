// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/default_type_arguments_test.go:27 TestDefaultTypeArgumentRules
type Trio[A, B, C = A] {
	first A
}

fn use(t Trio[Int]) Void => void
// expect-error: MS3000 8:10 Trio takes 2 to 3 type arguments, found 1; write Trio[T1, T2, T3]
