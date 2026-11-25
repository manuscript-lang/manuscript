// conform: tags=diagnostics
// conform: phase=check
fn f(value Float?) Void => return

fn call() Void => f(4)
// expect-error: MS3001 5:21 expected Float?, found Int (in argument 'value' of f)
