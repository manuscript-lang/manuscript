# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/callbacks_test.go:140 TestUnknownCallbackLabelDoesNotConflictWithInference
def example() -> Unit:
    choose(first: lambda: "a", second: lambda: "b", other: lambda: missing)
