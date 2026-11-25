// conform: tags=diagnostics
// conform: phase=check
fn f(g fn(value: Int) Int) Int => 1
// expect-error: MS1000 3:16-3:17 expected ')', found ':'; close the parenthesis, separating items with commas
