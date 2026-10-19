# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:59 TestDiagnosticsStateCauseAndFix
fn f() String:
    return [1].join(separator: ",")
