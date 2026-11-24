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
