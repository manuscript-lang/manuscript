// conform: tags=diagnostics
// conform: phase=check
fn probe() Int:
    var sum = 0
    var i = -1
    while i < 1000:
        if found := affine(i):
            sum += found
        i += 1
    return sum
