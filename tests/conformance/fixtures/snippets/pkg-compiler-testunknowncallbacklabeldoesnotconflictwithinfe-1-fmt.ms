# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:140 TestUnknownCallbackLabelDoesNotConflictWithInference
def example() -> Unit:
    choose(first: lambda: "a", second: lambda: "b", other: lambda: missing)
