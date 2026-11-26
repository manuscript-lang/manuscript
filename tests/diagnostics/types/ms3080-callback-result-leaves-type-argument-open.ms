// conform: tags=diagnostics
// conform: phase=check
fn run[T](operation fn() T!) Bool => return operation().is_error()

fn main() Void => print(run(() => error(Error("x"))))
// expect-error: MS3080 5:25 cannot infer type argument T for run; write run[T](...) with an explicit type for T; call arguments and the expected result must determine every type parameter
