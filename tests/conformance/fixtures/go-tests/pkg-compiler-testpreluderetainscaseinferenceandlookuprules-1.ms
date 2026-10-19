# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:12 TestPreludeRetainsCaseInferenceAndLookupRules
fn f() Unit:
    let missing = none
