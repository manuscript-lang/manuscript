# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/native_defaults_test.go:53 TestInheritedNativeDefaultsRejectDependenciesAndEffects
def f(first: Int = 1, value: Optional[Int] = none) -> Int: ...
