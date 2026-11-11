// conform: tags=diagnostics
// conform: phase=check
values := [1]
    peer := [2]
    var fill = 0
    while fill < 100:
        values.append(peer.get(-1))
        peer.append(values.get(-1))
        fill += 1