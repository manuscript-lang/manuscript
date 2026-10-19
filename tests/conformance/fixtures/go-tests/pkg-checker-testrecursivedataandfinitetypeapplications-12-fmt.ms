# conform: tags=formatter,parser,records,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:29 TestRecursiveDataAndFiniteTypeApplications
type Config:
    value: Result[Result[Int, Error], Error]
