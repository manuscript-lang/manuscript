// conform: tags=diagnostics
// conform: phase=check
fn probe() Int:
    var sum = 0
    var i = 0
    while i < 1000:
        if found := wrapped(i):
            sum += found
        i += 1
    return sum
