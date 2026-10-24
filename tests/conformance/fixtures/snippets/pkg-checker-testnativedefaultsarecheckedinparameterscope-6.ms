# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:20 TestNativeDefaultsAreCheckedInParameterScope
def f[T](value: T, copy: T = value) -> T: ...
