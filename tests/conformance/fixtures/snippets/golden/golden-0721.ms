// conform: tags=diagnostics
// conform: phase=check
fn first() Int:
    r: Result[Int, Error] := f()
    return h(r)