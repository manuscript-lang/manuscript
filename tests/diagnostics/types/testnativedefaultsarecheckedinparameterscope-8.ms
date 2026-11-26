// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/native_defaults_test.go:22 TestNativeDefaultsAreCheckedInParameterScope
fn f[T](value T, flag Int = 1 + 1) T { ... }
// expect-error: MS3000 4:1 reachable fallthrough in function returning T; end every path with 'return <T>' (or make the last branch return)
