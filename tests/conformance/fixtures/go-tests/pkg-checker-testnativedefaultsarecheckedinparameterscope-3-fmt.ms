# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/native_defaults_test.go:17 TestNativeDefaultsAreCheckedInParameterScope
fn f(first: Int = second, second: Int = 1) Int:
