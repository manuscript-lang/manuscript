// conform: tags=diagnostics
// conform: phase=check
    let b%d = ""
    var i%d = 0
    while i%d < 321 {
        b%d += %q
        i%d += 1
    }
    b%d.freeze()
    for x%d in values {
        sum += x%d
    }
// expect-error: MS1000 3:10-3:11 expected ':=', found '%'
