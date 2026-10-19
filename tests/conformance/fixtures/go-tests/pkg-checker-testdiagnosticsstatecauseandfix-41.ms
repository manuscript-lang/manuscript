# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:60 TestDiagnosticsStateCauseAndFix
fn double(n: Int) Int:
    return n * 2
fn f() Int:
    return [1, 2].map(double).length()
