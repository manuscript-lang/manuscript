// conform: tags=diagnostics
// conform: phase=check
fn before() Int: 0
fn broken() Int:
    return apply(
        op: fn(value: Int) Int:
            return value + 1,
        times: 3
    )
fn after() Int: 2
