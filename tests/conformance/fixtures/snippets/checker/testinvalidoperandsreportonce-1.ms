// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/invalid_operand_test.go:16 TestInvalidOperandsReportOnce
fn f() Int:
    x := nope
    return x + x
