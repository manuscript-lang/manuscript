// conform: tags=diagnostics
// conform: phase=check
var i = 0
    captured := match 0:
        n:
            i = start
            n
        none: 0