// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:13 TestPreludeRetainsCaseInferenceAndLookupRules
fn f() Unit:
    result := ok(value: 1)
