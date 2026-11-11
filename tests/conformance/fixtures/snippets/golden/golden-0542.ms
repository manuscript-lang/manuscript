// conform: tags=diagnostics
// conform: phase=check
values := [1]
    var fill = 0
    while fill < 100:
        values.append(values.get(-1) + 1)
        fill += 1