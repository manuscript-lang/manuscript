// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/default_type_arguments_test.go:24 TestDefaultTypeArgumentRules
fn f[A = Int, B](value B) B => value
// expect-error: MS3000 4:15 type parameter B needs a default because an earlier parameter has one; give B a default or move it before the defaulted parameters
