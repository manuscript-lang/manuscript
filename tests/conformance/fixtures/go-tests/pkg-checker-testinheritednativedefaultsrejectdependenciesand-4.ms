# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:54 TestInheritedNativeDefaultsRejectDependenciesAndEffects
fn f(value: Bytes = "".to_bytes()) Bytes:
