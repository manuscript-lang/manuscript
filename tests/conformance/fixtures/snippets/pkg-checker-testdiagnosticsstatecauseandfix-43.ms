# conform: tags=alternatives,diagnostics,match,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:62 TestDiagnosticsStateCauseAndFix
type S:
    case A
    case B

def f(s: S) -> Int:
    match s:
        case A:
            return 1
        case other:
            return 2
