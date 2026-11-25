// conform: tags=diagnostics
// conform: phase=check
fn f(x Int?) Int {
    return match x {
        n => {
            n
            n + 1
        }
        null => 0
    }
}
// expect-error: MS1000 6:13 an arm value must be its final expression
