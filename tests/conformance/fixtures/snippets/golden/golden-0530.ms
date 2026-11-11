// conform: tags=diagnostics
// conform: phase=check
fn probe(value: Int, flag: Bool) Int:
    var sum = value
    if flag:
        sum = 0
    else:
        sum += 1
    return sum
