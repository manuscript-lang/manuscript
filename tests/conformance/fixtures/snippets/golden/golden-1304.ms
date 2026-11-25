// conform: tags=diagnostics
// conform: phase=check
fn answer() Int => %d
// expect-error: MS1000 3:20-3:21 expected an expression, found '%'; write a value, name, call, or literal here
