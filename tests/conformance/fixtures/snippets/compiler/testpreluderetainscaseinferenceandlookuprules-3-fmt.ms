// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/prelude_test.go:14 TestPreludeRetainsCaseInferenceAndLookupRules
fn f() Unit:
    result := error(cause: "failed")
