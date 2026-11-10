// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/prelude_test.go:13 TestPreludeRetainsCaseInferenceAndLookupRules
fn f() Unit:
    result := ok(value: 1)
