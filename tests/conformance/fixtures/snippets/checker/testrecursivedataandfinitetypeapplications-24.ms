# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:41 TestRecursiveDataAndFiniteTypeApplications
type Flip[T, U]:
    next: Flip[U, T]
