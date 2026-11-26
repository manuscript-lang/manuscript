// conform: tags=diagnostics
// conform: phase=check
fn identity(n Int) Int => return n

fn probe(flag Bool) Int { ... }
// expect-error: MS3000 5:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
