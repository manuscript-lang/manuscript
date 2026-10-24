# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/native_defaults_test.go:52 TestInheritedNativeDefaultsRejectDependenciesAndEffects
def f(value: Int = (lambda () -> Int: 1)()) -> Int: ...
