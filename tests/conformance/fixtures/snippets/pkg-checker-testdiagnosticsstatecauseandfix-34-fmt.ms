# conform: tags=formatter,parser,sets,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:53 TestDiagnosticsStateCauseAndFix
fn f() Int:
    let _s = Set[String]()
    return 0
