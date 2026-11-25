// conform: tags=diagnostics
// conform: phase=check
fn f(value fn(x: Int = 1) Int) Void {
    return
}
// expect-error: MS1000 3:16-3:17 expected ')', found ':'; close the parenthesis, separating items with commas
