// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/default_type_arguments_test.go:25 TestDefaultTypeArgumentRules
fn f[A = B, B = Int](value B) B => value
// expect-error: MS2001 4:10 unknown type B; declare it with 'type B:' / 'enum B:' / 'interface B:', declare it as a type parameter, or import it
