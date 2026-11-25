// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/native_defaults_test.go:52 TestInheritedNativeDefaultsRejectDependenciesAndEffects
fn f(value Int = (fn() Int => 1)()) Int { ... }
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
