# conform: tags=faults,formatter,generics,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:43 TestPatternBindingAdvisory
fn use[T](value: T?) T:
    match value:
        some(Value): return Value
        none: return panic(message: "empty")
