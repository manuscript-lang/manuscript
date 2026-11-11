// conform: tags=diagnostics
// conform: phase=check
fn private_value() Int:
    return 7
export fn defaulted(value: Int = private_value()) Int:
    return value
