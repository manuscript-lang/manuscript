# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/callbacks_test.go:140 TestUnknownCallbackLabelDoesNotConflictWithInference
fn example() Unit:
    choose(first: fn: "a", second: fn: "b", other: fn: missing)
