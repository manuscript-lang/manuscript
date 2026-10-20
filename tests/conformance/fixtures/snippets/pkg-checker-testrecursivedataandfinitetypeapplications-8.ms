# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:25 TestRecursiveDataAndFiniteTypeApplications
type Box[T]:
    value: T
type Nested:
    value: Box[Box[Int]]
