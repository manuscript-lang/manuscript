// conform: tags=diagnostics
// conform: phase=check
fn work() Int {
    bad := = 1
    return 1
}
// expect-error: MS1000 4:12-4:13 expected an expression, found '='; write a value, name, call, or literal here
