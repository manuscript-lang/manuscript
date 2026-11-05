// conform: tags=alternatives,diagnostics,match,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:35 TestDiagnosticsStateCauseAndFix
enum S:
    A
    B
    C

fn f(s: S) Int:
    match s:
        A:
            return 1

    return 0
