// conform: tags=diagnostics
// conform: phase=check
fn probe() Int:
    var sum = 9223372036854775807
    var i = 0
    while i < 321:
        sum += i
        i += 1
    return sum
