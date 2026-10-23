# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_test.go:136 TestFormatCommentsAndErrors
# leading
fn sum(left: Int, right: Int) Int:  # sum
    return left + right  # trailing
