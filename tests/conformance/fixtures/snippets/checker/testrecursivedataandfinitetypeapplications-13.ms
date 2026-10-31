# conform: tags=diagnostics,optional,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:30 TestRecursiveDataAndFiniteTypeApplications
type Pair[T, U]:
    first: T
    second: U

type Config:
    value: Pair[Int?, String??]
