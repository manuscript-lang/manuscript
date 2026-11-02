# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/native_defaults_test.go:54 TestInheritedNativeDefaultsRejectDependenciesAndEffects
fn f(value: Bytes = "".to_bytes()) Bytes: ...
