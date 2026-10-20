# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/partial_continuation_test.go:93 TestPartialContinuationDifferential
fn later(
value: Int = 3,
) Int:
    return value
