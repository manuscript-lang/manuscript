// conform: tags=diagnostics
// conform: phase=check
fn use(value: Result[Int, Error]) Int:
    if n := value:
        return n
    return 0
