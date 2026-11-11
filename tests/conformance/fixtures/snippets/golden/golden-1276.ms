// conform: tags=diagnostics
// conform: phase=check
fn read() Int:
    return 1
fn named(value: Int = read()) Int:
    return value
