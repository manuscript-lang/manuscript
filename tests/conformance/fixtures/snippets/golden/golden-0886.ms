// conform: tags=diagnostics
// conform: phase=check
fn g(x Int) Int {
    return x
}
fn f() Int {
    return g(x = 1)
}
// expect-error: MS1000 7:16-7:17 argument labels use a colon; write x: value
