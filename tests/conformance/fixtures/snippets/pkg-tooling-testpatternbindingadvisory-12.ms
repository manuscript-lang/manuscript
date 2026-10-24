# conform: tags=diagnostics,faults,generics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:43 TestPatternBindingAdvisory
def use[T](value: Optional[T]) -> T:
    match value:
        case some(Value): return Value
        case none: return panic(message: "empty")
