# conform: tags=formatter,lists,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:31 TestRecursiveDataAndFiniteTypeApplications
type Config:
    value: Optional[List[Optional[Int]]]
