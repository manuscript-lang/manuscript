// conform: tags=diagnostics
// conform: phase=check
fn probe(value Int) Int => return value %% %d
// expect-error: MS1000 3:42-3:43 expected an expression, found '%'; write a value, name, call, or literal here
