# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/native_defaults_test.go:18 TestNativeDefaultsAreCheckedInParameterScope
def f(value: Int = value) -> Int: ...
