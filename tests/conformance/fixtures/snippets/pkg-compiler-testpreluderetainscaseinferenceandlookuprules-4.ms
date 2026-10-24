# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:15 TestPreludeRetainsCaseInferenceAndLookupRules
def f() -> Error:
    return "failed"
