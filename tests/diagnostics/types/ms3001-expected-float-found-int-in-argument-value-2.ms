// conform: tags=diagnostics
// conform: phase=check
fn f(value Float?) Void => return

fn call(value Int?) Void => f(value)
// expect-error: MS3001 5:31 expected Float?, found Int? (in argument 'value' of f)
