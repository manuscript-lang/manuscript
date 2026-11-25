// conform: tags=diagnostics,formatter,generics,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/optional_test.go:34 TestOptionalArgumentBoundaries
fn f[T](value T?) Void => return

fn call() Void => f()
// expect-error: MS3080 6:19 cannot infer type argument T for f; write f[T](...) with an explicit type for T; call arguments and the expected result must determine every type parameter
