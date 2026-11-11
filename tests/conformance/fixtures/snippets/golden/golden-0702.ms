// conform: tags=diagnostics
// conform: phase=check

fn probe() Int:
    cell := Cell(0)
    var i = 0
    while i < 1000:
        cell.bump(1)
        i += 1
    return cell.total
