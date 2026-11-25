// conform: tags=diagnostics
// conform: phase=check
fn f() Void => return

fn g() Void => return
// expect-exit: 0
