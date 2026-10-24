# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/native_defaults_test.go:15 TestNativeDefaultsAreCheckedInParameterScope
def f(first: Int, second: Int = first + 1) -> Int: ...
