# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/native_defaults_test.go:20 TestNativeDefaultsAreCheckedInParameterScope
fn f[T](value: T, copy: T = value) T:
