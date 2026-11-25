// conform: tags=diagnostics
// conform: phase=check
fn f(callback fn(value: Int = 3) Int) Void => return
// expect-error: MS1000 3:23-3:24 expected ')', found ':'; close the parenthesis, separating items with commas
