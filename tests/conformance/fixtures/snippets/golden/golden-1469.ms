// conform: tags=diagnostics
// conform: phase=check
fn crash(value: Int) Int?:
    return (1 / value)
export fn main() Int:
    value: Int? := 0
    return value.and_then(crash).get()
