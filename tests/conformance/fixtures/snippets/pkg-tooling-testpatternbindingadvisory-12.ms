# conform: tags=diagnostics,faults,generics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:43 TestPatternBindingAdvisory
fn use[T](value: T?) T:
    match value:
        some(Value): return Value
        none: return panic(message: "empty")
