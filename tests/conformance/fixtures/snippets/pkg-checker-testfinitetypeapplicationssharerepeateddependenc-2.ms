# conform: tags=parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:87 TestFiniteTypeApplicationsShareRepeatedDependencies
type Layer%d[T]:
    left: Layer%d[T]
    right: Layer%d[T]
