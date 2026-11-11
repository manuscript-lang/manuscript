// conform: tags=diagnostics
// conform: phase=check
fn work() Int:
    values := [1, 2]
    var i = 0
    var total = 0
    while i < 2:
        total += values.get(i)
        i += 1
    return total
