// conform: tags=diagnostics
// conform: phase=check
fn f(value Int?) Void => return

fn call() Void => f(4, value: 5)
