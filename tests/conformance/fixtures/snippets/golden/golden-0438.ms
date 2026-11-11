// conform: tags=diagnostics
// conform: phase=check
var value = 1
    values := [1].map(fn(item):
        value = 2
        return item
    )