# conform: tags=diagnostics,faults,generics,match,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:30 TestPatternBindingAdvisory
type Box[T]:
    value: T
fn use[T](value: Optional[Box[T]]) T:
    match value:
        some(Box): return Box.value
        none: return panic(message: "empty")
