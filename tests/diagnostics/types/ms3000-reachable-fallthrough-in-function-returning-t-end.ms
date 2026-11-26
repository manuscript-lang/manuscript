// conform: tags=diagnostics
// conform: phase=check
fn f[T](value T? = null) T? { ... }
// expect-error: MS3000 3:1 reachable fallthrough in function returning T?; end every path with 'return <T?>' (or make the last branch return)
