// conform: tags=diagnostics
// conform: phase=check
export type Value:
    value: Int
export fn read(value: Value) Int:
    return value.value
fn hidden() Int:
    return 1
