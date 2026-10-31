# conform: tags=diagnostics,lists,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:31 TestRecursiveDataAndFiniteTypeApplications
type Config:
    value: List[Int?]?
