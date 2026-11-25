// conform: tags=diagnostics
// conform: phase=check
fn before() Void => void

fn broken() Void { ... }
// expect-exit: 0
