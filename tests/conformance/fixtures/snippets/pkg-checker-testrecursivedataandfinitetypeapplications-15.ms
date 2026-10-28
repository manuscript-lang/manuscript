# conform: tags=closures,diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:32 TestRecursiveDataAndFiniteTypeApplications
type Node[T]:
    build: fn() Node[T]
