// conform: tags=diagnostics
// conform: phase=check
fn choose(value: Choice) Int:
    match value:
        first: return 1
        second: return 2
        third:
            result := calculate()
            return result
        _: return 0
    return 3
