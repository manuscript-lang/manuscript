# conform: tags=alternatives,formatter,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:28 TestRecursiveDataAndFiniteTypeApplications
type Config:
    case Value(value: Optional[Optional[Int]])
