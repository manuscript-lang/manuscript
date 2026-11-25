// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/native_defaults_test.go:19 TestNativeDefaultsAreCheckedInParameterScope
fn f(value Bool = null) Bool { ... }
// expect-error: MS3001 4:19 expected Bool, found null; null is absent, so it fits only an Optional position: declare the target Bool? or give a value
// expect-error: MS3000 4:1 reachable fallthrough in function returning Bool; end every path with 'return <Bool>' (or make the last branch return)
