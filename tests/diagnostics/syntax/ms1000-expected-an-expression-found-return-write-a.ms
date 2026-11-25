// conform: tags=diagnostics
// conform: phase=check
fn f() Void => return return
// expect-error: MS1000 3:23-3:29 expected an expression, found 'return'; write a value, name, call, or literal here
