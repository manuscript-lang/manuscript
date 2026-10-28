# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:54 TestDiagnosticsStateCauseAndFix
fn f() Int:
    let s = SetBuilder[String]()
    return 0
