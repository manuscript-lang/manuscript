# conform: tags=diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/invalid_operand_test.go:19 TestInvalidOperandsReportOnce
def f() -> String:
    let x = nope
    return "a" + x.foo + x.bar()
