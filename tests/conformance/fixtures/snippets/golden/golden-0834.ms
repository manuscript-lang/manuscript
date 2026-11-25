// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
    total + = 1
}
// expect-error: MS1000 4:13-4:14 expected an expression, found '='; write a value, name, call, or literal here
