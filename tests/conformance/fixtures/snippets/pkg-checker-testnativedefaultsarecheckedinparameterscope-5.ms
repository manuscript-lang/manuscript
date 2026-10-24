# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:19 TestNativeDefaultsAreCheckedInParameterScope
def f(value: Bool = none) -> Bool: ...
