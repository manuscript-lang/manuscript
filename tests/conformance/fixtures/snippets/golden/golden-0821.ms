// conform: tags=diagnostics
// conform: phase=check
    var i = 0
    while i < 4:
        read := fn() Int:
            return values.get(0)
        total += read()
        i += 1
