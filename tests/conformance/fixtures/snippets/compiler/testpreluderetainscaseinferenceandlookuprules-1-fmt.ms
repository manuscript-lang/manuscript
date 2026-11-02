# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:12 TestPreludeRetainsCaseInferenceAndLookupRules
fn f() Unit:
    let missing = none
