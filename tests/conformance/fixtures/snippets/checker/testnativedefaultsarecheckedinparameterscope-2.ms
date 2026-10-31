# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:16 TestNativeDefaultsAreCheckedInParameterScope
fn f(value: Int = true) Int: ...
