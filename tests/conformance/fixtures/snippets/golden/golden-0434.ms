// conform: tags=diagnostics
// conform: phase=check
value := choose(first: fn():
        if true: return null
        return 1
    , second: fn(): 2)