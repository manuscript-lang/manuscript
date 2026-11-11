// conform: tags=diagnostics
// conform: phase=check
fn apply(transform: fn(Int) Int, value: Int) Int: transform(value)
fn example() Int:
    return apply(
        transform: fn(value: Int) Int:
            return value - 1
        ,
        value: 3,
    )
