# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:14 TestPreludeRetainsCaseInferenceAndLookupRules
def f() -> Unit:
    let result = error(cause: "failed")
