// conform: tags=diagnostics
// conform: phase=check
fn use(value: Result[Int, Error]) Int:
    return value.get(0)
