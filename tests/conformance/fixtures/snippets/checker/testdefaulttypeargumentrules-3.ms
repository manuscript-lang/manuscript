# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/default_type_arguments_test.go:25 TestDefaultTypeArgumentRules
fn f[A = B, B = Int](value: B) B: value
