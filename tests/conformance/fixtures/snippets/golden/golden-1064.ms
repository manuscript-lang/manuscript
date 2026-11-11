// conform: tags=diagnostics
// conform: phase=check
prices := [12, 8, 25]
affordable := (
    prices.length > 1
    and prices.keep(
        predicate: fn(value: Int) Bool:
            return value <= 10
    ).length > 0
)
