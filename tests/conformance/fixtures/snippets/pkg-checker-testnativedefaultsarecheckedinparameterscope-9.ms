# conform: tags=diagnostics,generics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:23 TestNativeDefaultsAreCheckedInParameterScope
fn f[T](value: Optional[T] = none) Optional[T]: ...
