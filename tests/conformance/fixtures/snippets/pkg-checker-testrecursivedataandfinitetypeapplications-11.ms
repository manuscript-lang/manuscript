# conform: tags=alternatives,diagnostics,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:28 TestRecursiveDataAndFiniteTypeApplications
type Config:
    case Value(value: Optional[Optional[Int]])
