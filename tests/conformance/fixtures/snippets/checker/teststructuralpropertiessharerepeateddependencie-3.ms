// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/layout_diagnostics_test.go:105 TestStructuralPropertiesShareRepeatedDependencies
fn hash(value Layer32) Int => return value.hash()
// expect-error: MS2001 4:15 unknown type Layer32; declare it with 'type Layer32:' / 'enum Layer32:' / 'interface Layer32:', declare it as a type parameter, or import it
