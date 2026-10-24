# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/native_defaults_test.go:52 TestInheritedNativeDefaultsRejectDependenciesAndEffects
def f(value: Int = (lambda () -> Int: 1)()) -> Int: ...
