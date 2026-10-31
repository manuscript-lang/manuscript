# conform: tags=formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/native_defaults_test.go:23 TestNativeDefaultsAreCheckedInParameterScope
fn f[T](value: T?) T?: ...
