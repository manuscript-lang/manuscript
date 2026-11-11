// conform: tags=diagnostics
// conform: phase=check
fn probe(value: Int) Int:
    var sum = 0
    sum = value
    callback := fn() Int:
        return sum + value
    return callback()
