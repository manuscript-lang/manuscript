# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/invalid_operand_test.go:19 TestInvalidOperandsReportOnce
fn f() String:
    let x = nope
    return "a" + x.foo + x.bar()
