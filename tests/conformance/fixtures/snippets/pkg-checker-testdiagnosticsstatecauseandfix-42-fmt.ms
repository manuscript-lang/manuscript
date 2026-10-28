# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:61 TestDiagnosticsStateCauseAndFix
fn positive(n: Int) Bool:
    return n > 0

fn f() Int:
    return [1].filter(positive).length()
