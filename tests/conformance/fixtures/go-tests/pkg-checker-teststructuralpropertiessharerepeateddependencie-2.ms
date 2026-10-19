# conform: tags=parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:103 TestStructuralPropertiesShareRepeatedDependencies
type Layer%d:
    left: Layer%d
    right: Layer%d
