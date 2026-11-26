// conform: tags=diagnostics
// conform: phase=check
fn f[T](value T? = null) Void => return

fn call() Void => f()
// expect-error: MS3080 5:19 cannot infer type argument T for f; write f[T](...) with an explicit type for T; call arguments and the expected result must determine every type parameter
