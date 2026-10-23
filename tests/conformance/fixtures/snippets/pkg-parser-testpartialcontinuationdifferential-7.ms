# conform: tags=diagnostics,interpolation,strings,tier-core
# conform: phase=check
# conform: origin=pkg/parser/partial_continuation_test.go:98 TestPartialContinuationDifferential
fn later(letter: String = "{1 + 2}", interface_name: Int = 1) Int:
    return 1
