# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:106 TestStructuralPropertiesShareRepeatedDependencies
fn equal(left: Layer32, right: Layer32) Bool: return left == right
