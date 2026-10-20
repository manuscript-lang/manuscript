# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:18 TestNativeDefaultsAreCheckedInParameterScope
fn f(value: Int = value) Int:
