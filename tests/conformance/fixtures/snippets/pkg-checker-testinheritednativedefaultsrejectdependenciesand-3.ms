# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:53 TestInheritedNativeDefaultsRejectDependenciesAndEffects
def f(first: Int = 1, value: Optional[Int] = none) -> Int: ...
