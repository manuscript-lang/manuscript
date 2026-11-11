// conform: tags=diagnostics
// conform: phase=check
fn probe() Int:
    var sum = 0
    var i = 0
    while i < 255:
        sum += 3
        i += 1
    return sum
