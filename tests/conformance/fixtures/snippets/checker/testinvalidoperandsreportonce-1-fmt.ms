// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/invalid_operand_test.go:16 TestInvalidOperandsReportOnce
fn f() Int:
    x := nope
    return x + x
