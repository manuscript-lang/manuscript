// conform: tags=diagnostics
// conform: phase=check
fn read(values: List[Int]) Int:
    if first := values.first():
        return first + 1
    return 0
