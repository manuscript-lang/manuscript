# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:51 TestInheritedNativeDefaultsRejectDependenciesAndEffects
fn f(first: Int, value: Int = first) Int: ...
