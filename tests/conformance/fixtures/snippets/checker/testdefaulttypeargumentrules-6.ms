// conform: tags=diagnostics,generics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/checker/default_type_arguments_test.go:28 TestDefaultTypeArgumentRules
fn make[T, U = Int]() T? => null

fn use() Void {
	x := make()
}
// expect-error: MS3080 7:10 cannot infer type argument T for make; write make[T, Int](...) with an explicit type for T; call arguments and the expected result must determine every type parameter
