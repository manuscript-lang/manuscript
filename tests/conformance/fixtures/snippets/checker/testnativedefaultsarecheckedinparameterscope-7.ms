# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:21 TestNativeDefaultsAreCheckedInParameterScope
fn f[T](value: T, flag: Bool = true) T: ...
