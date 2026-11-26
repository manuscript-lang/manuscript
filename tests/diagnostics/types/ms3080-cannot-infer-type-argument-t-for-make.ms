// conform: tags=diagnostics
// conform: phase=check
fn make[T, U = Int]() T? => null

fn use() Void {
	x := make()
}
// expect-error: MS3080 6:10 cannot infer type argument T for make; write make[T, Int](...) with an explicit type for T; call arguments and the expected result must determine every type parameter
