// conform: tags=diagnostics
// conform: phase=check
fn f(first Int = 1, value Int? = null) Int { ... }
// expect-error: MS3000 3:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
