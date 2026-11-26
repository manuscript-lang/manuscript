// conform: tags=diagnostics
// conform: phase=check
fn run[T](operation fn() T!) Bool => return operation().is_error()

fn main() Void => print(run(() => ok(1)))
