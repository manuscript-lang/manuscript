# conform: tags=diagnostics,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:27 TestRecursiveDataAndFiniteTypeApplications
type Config:
    value: Optional[Optional[Int]]
