# conform: tags=alternatives,control-flow,diagnostics,interfaces,match,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:44 TestPatternBindingAdvisory
type Failure:
    case NotFound
    case Denied(reason: String)

impl Error for Failure:
    fn message() String: "f"

fn failure_code(cause: Failure) Int:
    match cause:
        NotFound: return 1
        Denied(_): return 2

fn classify(result: Int!Failure) Int:
    match result:
        error(cause): return failure_code(cause)
        ok(value): return value
