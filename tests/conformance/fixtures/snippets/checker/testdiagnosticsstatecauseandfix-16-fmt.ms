// conform: tags=alternatives,formatter,match,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/hints_test.go:35 TestDiagnosticsStateCauseAndFix
enum S:
    case A
    case B
    case C

fn f(s: S) Int:
    match s:
        A:
            return 1

    return 0
