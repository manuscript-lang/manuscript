// conform: tags=diagnostics
// conform: phase=check
    let b%d = StringBuilder()
    var i%d = 0
    while i%d < 321:
        b%d.append(%q)
        i%d += 1
    b%d.freeze()
    for x%d in values:
        sum += x%d
