# conform: tags=alternatives,diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:20 TestRecursiveDataAndFiniteTypeApplications
type A:
    case End
    case Next(value: B)
type B:
    a: A
