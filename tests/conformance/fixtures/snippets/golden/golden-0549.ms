// conform: tags=diagnostics
// conform: phase=check
fn probe(value: Int) Int:
    values := [1, 2, 3]
    callback := fn() Int:
        var sum = value
        for item in values:
            sum += item
        return sum
    return callback()
