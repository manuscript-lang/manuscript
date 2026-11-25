// conform: tags=diagnostics
// conform: phase=check
fn identity[T](value T) T => value

fn first() Int { ... }
// expect-error: MS3000 5:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
