# conform: tags=faults,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:21 TestDiagnosticsStateCauseAndFix
fn f() Unit:
    return panic(message: "x")
