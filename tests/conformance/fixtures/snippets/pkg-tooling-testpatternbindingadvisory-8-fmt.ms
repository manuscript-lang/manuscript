# conform: tags=faults,formatter,generics,match,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:30 TestPatternBindingAdvisory
type Box[T]:
    value: T

fn use[T](value: Box[T]?) T:
    match value:
        some(Box): return Box.value
        none: return panic(message: "empty")
