// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/invalid_operand_test.go:18 TestInvalidOperandsReportOnce
fn f() Bool:
    x := nope
    return x and x
