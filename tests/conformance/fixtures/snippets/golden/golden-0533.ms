// conform: tags=diagnostics
// conform: phase=check
fn probe() Int:
    var sum = 0
    var i = 0
    while i < 100:
        sum += i
        i += 1
    return sum
