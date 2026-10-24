# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:18 TestNativeDefaultsAreCheckedInParameterScope
def f(value: Int = value) -> Int: ...
