// conform: tags=diagnostics
// conform: phase=check
fn work() Int:
    return apply(value: 3, transform: fn(value: Int) Int:
        if value == 0: return 0
        next := value + 1
        return next
    )
