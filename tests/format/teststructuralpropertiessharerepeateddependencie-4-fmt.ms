// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:106 TestStructuralPropertiesShareRepeatedDependencies
fn equal(left Layer32, right Layer32) Bool => return left == right
// expect-format: rewritten
// expect-formatted: fn equal(left, right Layer32) Bool => return left == right
