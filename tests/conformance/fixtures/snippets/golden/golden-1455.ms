// conform: tags=diagnostics
// conform: phase=check
fn probe() Int:
    values := [1, 2, 3]
    var sum = 9223372036854775807
    for x in values:
        sum += x
    return sum
export fn main() Int:
    return probe()
