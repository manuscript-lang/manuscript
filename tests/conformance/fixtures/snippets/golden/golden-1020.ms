// conform: tags=diagnostics
// conform: phase=check
    values := [0]
    operation := fn(): values.append(1)
    _result := operation()
