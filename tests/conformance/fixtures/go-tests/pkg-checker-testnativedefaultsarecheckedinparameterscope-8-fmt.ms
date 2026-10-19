# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/native_defaults_test.go:22 TestNativeDefaultsAreCheckedInParameterScope
fn f[T](value: T, flag: Int = 1 + 1) T:
