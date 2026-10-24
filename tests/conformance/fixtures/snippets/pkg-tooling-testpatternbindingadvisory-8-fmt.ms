# conform: tags=faults,formatter,generics,match,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:30 TestPatternBindingAdvisory
type Box[T]:
    value: T

def use[T](value: Optional[Box[T]]) -> T:
    match value:
        case some(Box): return Box.value
        case none: return panic(message: "empty")
