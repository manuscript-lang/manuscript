# conform: tags=alternatives,diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/ambiguous_case_test.go:16 TestAmbiguousCaseReportsOnce
type A:
    case X

type B:
    case X

def f() -> Int:
    let a = X
    return 1
