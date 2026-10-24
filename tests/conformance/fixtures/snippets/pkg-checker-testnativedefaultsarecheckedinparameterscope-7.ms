# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:21 TestNativeDefaultsAreCheckedInParameterScope
def f[T](value: T, flag: Bool = True) -> T: ...
