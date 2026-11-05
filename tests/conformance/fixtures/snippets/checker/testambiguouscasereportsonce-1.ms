// conform: tags=alternatives,diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/ambiguous_case_test.go:16 TestAmbiguousCaseReportsOnce
enum A:
    case X

enum B:
    case X

fn f() Int:
    let a = X
    return 1
