# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:13 TestPreludeRetainsCaseInferenceAndLookupRules
def f() -> Unit:
    let result = ok(value: 1)
