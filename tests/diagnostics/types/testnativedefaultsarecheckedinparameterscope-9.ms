// conform: tags=diagnostics,formatter,generics,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/native_defaults_test.go:23 TestNativeDefaultsAreCheckedInParameterScope
fn f[T](value T?) T? { ... }
// expect-error: MS3000 4:1 reachable fallthrough in function returning T?; end every path with 'return <T?>' (or make the last branch return)
