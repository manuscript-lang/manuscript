// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/native_defaults_test.go:15 TestNativeDefaultsAreCheckedInParameterScope
fn f(first Int, second Int = first + 1) Int { ... }
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
