# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/e2e_test.go:505 TestDefaultArgumentsAcrossModules
fn private_value() Int:
    return 7
export fn defaulted(value: Int = private_value()) Int:
    return value
