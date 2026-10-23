# conform: tags=alternatives,diagnostics,match,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:35 TestDiagnosticsStateCauseAndFix
type S:
    case A
    case B
    case C

fn f(s: S) Int:
    match s:
        A:
            return 1

    return 0
