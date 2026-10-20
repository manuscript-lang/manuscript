# conform: tags=diagnostics,records,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:29 TestRecursiveDataAndFiniteTypeApplications
type Config:
    value: Result[Result[Int, Error], Error]
