// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/invalid_operand_test.go:18 TestInvalidOperandsReportOnce
fn f() Bool:
    x := nope
    return x and x
