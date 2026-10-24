# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:17 TestNativeDefaultsAreCheckedInParameterScope
def f(first: Int = second, second: Int = 1) -> Int: ...
