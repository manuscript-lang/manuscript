// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    x = 
    return 1
}
// expect-error: MS1000 4:9-4:9 expected an expression, found end of line; write a value, name, call, or literal here
