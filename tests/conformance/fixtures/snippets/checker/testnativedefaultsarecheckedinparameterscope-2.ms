// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/native_defaults_test.go:16 TestNativeDefaultsAreCheckedInParameterScope
fn f(value Int = true) Int { ... }
// expect-error: MS3001 4:18 expected Int, found Bool
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
