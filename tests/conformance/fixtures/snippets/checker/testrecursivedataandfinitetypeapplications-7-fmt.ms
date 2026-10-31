# conform: tags=formatter,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:24 TestRecursiveDataAndFiniteTypeApplications
type Phantom[T]:
    value: Int

type Grow[T]:
    value: Phantom[Grow[List[T]]]
