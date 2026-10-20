# conform: tags=alternatives,formatter,match,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:62 TestDiagnosticsStateCauseAndFix
type S:
    case A
    case B
fn f(s: S) Int:
    match s:
        A:
            return 1
        other:
            return 2
