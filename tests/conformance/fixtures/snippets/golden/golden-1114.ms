// conform: tags=diagnostics
// conform: phase=check
fn example() Int:
    result := apply(
        value: 3,
        transform: (
            fn(value: Int) Int:
                if value == 0: return 0

                next := value + 1
                return next
        )
    )
    return result
