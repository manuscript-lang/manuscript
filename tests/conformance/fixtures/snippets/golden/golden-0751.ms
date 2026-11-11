// conform: tags=diagnostics
// conform: phase=check
fn probe(found: Int) Int:
    var sum = 0
    var i = 0
    while i < 1000:
        if found := affine(i):
            sum += found
        else:
            sum += found
        i += 1
    return sum
