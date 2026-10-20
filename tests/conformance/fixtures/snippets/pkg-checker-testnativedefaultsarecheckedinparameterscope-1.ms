# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:15 TestNativeDefaultsAreCheckedInParameterScope
fn f(first: Int, second: Int = first + 1) Int:
