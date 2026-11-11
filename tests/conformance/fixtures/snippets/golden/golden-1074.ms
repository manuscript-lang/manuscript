// conform: tags=diagnostics
// conform: phase=check
fn work() Int:
    var total = 1
    total+=2
    total   *=   3
    box.count -=  total
    return total
