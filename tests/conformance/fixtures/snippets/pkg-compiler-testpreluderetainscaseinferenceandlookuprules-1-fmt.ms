# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:12 TestPreludeRetainsCaseInferenceAndLookupRules
def f() -> Unit:
    let missing = none
