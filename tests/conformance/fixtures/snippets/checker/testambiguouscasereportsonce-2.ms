// conform: tags=alternatives,diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/ambiguous_case_test.go:17 TestAmbiguousCaseReportsOnce
enum A:
    case X(n: Int)

enum B:
    case X(n: Int)

fn f() Int:
    let a = X(n: 1)
    return 1
