# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:13 TestPreludeRetainsCaseInferenceAndLookupRules
def f() -> Unit:
    let result = ok(value: 1)
