// conform: tags=diagnostics
// conform: phase=check
fn f(value Int?) Void => return

fn call() Void => f(other: 4)
// expect-error: MS3004 5:21 unknown argument other; parameters of f: value
