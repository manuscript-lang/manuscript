// conform: tags=diagnostics
// conform: phase=check
    let list%d = [1, 2, 3]
    let cell%d = Cell(0)
    var i%d = 0
    while i%d < 1000 {
        cell%d.bump(1)
        sum += list%d.length()
        i%d += 1
    }
// expect-error: MS1000 3:13-3:14 expected ':=', found '%'
