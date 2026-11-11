// conform: tags=diagnostics
// conform: phase=check
fn answer(value: Int = (fn() Int:
    var current = 0
    current = current + 1
    return current
)()) Int:
    callbacks := [
        fn() Int:
            nested := 1
            return nested
    ]
    return value + callbacks.length()
