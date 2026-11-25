// conform: tags=diagnostics
// conform: phase=check
fn identity(hold callback fn(Int) Int) &fn(Int) Int => callback

fn use(callback fn(Int) Int) Int => identity(callback)(2)
