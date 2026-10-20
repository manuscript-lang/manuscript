# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=tests/e2e/e2e_test.go:505 TestDefaultArgumentsAcrossModules
fn private_value() Int:
    return 7
export fn defaulted(value: Int = private_value()) Int:
    return value
