# conform: tags=faults,formatter,generics,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:43 TestPatternBindingAdvisory
def use[T](value: Optional[T]) -> T:
    match value:
        case some(Value): return Value
        case none: return panic(message: "empty")
