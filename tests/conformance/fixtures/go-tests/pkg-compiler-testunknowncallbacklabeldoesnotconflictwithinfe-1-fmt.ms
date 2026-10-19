# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:140 TestUnknownCallbackLabelDoesNotConflictWithInference
fn example() Unit:
    choose(first: fn(): "a", second: fn(): "b", other: fn(): missing)
