# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/native_defaults_test.go:21 TestNativeDefaultsAreCheckedInParameterScope
def f[T](value: T, flag: Bool = True) -> T: ...
