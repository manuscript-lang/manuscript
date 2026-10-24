# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:15 TestPreludeRetainsCaseInferenceAndLookupRules
def f() -> Error:
    return "failed"
