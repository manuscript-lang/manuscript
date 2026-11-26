// conform: tags=diagnostics
// conform: phase=check
    let captured%d = fn() Int => unrelated
    sum = 0
    var i%d = 0
    while i%d < 321 {
        sum += i%d
        i%d += 1
    }
// expect-error: MS1000 3:17-3:18 expected ':=', found '%'
