// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:14 TestPreludeRetainsCaseInferenceAndLookupRules
fn f() Unit:
    result := error(cause: "failed")
