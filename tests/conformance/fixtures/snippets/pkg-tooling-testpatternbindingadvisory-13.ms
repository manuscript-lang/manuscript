# conform: tags=alternatives,control-flow,diagnostics,interfaces,match,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:44 TestPatternBindingAdvisory
type Failure:
    case NotFound
    case Denied(reason: String)

impl Error for Failure:
    def message() -> String: "f"

def failure_code(cause: Failure) -> Int:
    match cause:
        case NotFound: return 1
        case Denied(_): return 2

def classify(result: Result[Int, Failure]) -> Int:
    match result:
        case error(cause): return failure_code(cause)
        case ok(value): return value
