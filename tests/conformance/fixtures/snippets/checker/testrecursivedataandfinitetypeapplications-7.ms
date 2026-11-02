# conform: tags=diagnostics,lists,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:24 TestRecursiveDataAndFiniteTypeApplications
type Phantom[T]:
    value: Int

type Grow[T]:
    value: Phantom[Grow[List[T]]]
