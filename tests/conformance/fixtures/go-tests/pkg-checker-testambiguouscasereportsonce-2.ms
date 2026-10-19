# conform: tags=alternatives,diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/ambiguous_case_test.go:17 TestAmbiguousCaseReportsOnce
type A:
    case X(n: Int)
type B:
    case X(n: Int)
fn f() Int:
    let a = X(n: 1)
    return 1
