// conform: tags=diagnostics
// conform: phase=check
fn f(value Int?) Void => return

fn call() Void => f(4, value: 5)
// expect-error: MS3002 5:24 duplicate argument value; pass each argument once
