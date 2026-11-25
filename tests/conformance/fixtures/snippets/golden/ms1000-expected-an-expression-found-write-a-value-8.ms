// conform: tags=diagnostics
// conform: phase=check
fn a() Int {
    if true {
        y := = 3
        z := 1
    }
    w := = 4
    return 1
}
// expect-error: MS1000 5:14-5:15 expected an expression, found '='; write a value, name, call, or literal here
// expect-error: MS1000 8:10-8:11 expected an expression, found '='; write a value, name, call, or literal here
