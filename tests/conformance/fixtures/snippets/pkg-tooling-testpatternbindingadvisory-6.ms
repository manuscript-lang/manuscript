# conform: tags=alternatives,control-flow,diagnostics,generics,interfaces,match,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:28 TestPatternBindingAdvisory
type Failure[T]:
    case NotFound
    case Denied(reason: T)

impl Error for Failure[T]:
    def message() -> String: "f"

def use[T](value: Result[Int, Failure[T]]) -> Int:
    match value:
        case error(NotFound): return 1
        case ok(value): return value
