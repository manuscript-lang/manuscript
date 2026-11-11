// conform: tags=diagnostics
// conform: phase=check
    var i%d = 0
    while i%d < 1000:
        if found := affine%d(i%d):
            sum += found
        else:
            sum -= 1
        i%d += 1
