// conform: tags=diagnostics
// conform: phase=check
fn a() Int {
    if true {
        y := = 3
    }
    return 1
}
// expect-error: MS1000 5:14-5:15 expected an expression, found '='; write a value, name, call, or literal here
