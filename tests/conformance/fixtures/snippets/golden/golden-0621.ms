// conform: tags=diagnostics
// conform: phase=check
fn f(value Int?) Void => return

fn call() Void => f("wrong")
// expect-error: MS3001 5:21 expected Int?, found String (in argument 'value' of f)
