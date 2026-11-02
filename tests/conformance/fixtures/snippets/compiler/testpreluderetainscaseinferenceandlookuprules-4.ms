# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:15 TestPreludeRetainsCaseInferenceAndLookupRules
fn f() Error:
    return "failed"
