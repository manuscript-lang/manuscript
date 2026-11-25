// conform: tags=diagnostics
// conform: phase=check
fn identity[T](value T) T => return value

fn effect(value Int) Int => return value + 1

fn probe(start Int, flag Bool) Int { ... }
// expect-error: MS3000 7:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
