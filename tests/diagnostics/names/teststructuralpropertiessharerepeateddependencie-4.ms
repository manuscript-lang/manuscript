// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/layout_diagnostics_test.go:106 TestStructuralPropertiesShareRepeatedDependencies
fn equal(left Layer32, right Layer32) Bool => return left == right
// expect-error: MS2001 4:15 unknown type Layer32; declare it with 'type Layer32:' / 'enum Layer32:' / 'interface Layer32:', declare it as a type parameter, or import it
// expect-error: MS2001 4:30 unknown type Layer32; declare it with 'type Layer32:' / 'enum Layer32:' / 'interface Layer32:', declare it as a type parameter, or import it
