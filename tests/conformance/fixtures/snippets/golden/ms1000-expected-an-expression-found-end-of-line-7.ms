// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
    value = 
}
// expect-error: MS1000 4:13-4:13 expected an expression, found end of line; write a value, name, call, or literal here
