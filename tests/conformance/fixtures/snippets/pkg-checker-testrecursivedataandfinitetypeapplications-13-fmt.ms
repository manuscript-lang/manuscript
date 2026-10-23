# conform: tags=formatter,optional,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:30 TestRecursiveDataAndFiniteTypeApplications
type Pair[T, U]:
    first: T
    second: U

type Config:
    value: Pair[Optional[Int], Optional[Optional[String]]]
