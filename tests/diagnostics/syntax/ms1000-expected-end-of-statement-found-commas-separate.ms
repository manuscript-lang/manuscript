// conform: tags=diagnostics
// conform: phase=check
fn before() Int => 0
fn broken() Int {
    return apply(
        op: fn(value Int) Int {
            return value + 1,
        }
        times: 3
    )
}
fn after() Int => 2
// expect-error: MS1000 7:29-7:30 expected end of statement, found ','; commas separate items only inside (), [] or {}: put each field, case, or statement on its own line
