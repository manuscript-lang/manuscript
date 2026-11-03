# conform: tags=alternatives,control-flow,formatter,interfaces,match,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:44 TestPatternBindingAdvisory
type Failure:
    case NotFound
    case Denied(reason: String)

fn failure_code(cause: Failure) Int:
    match cause:
        NotFound: return 1
        Denied(_): return 2

fn classify(result: Int!Failure) Int:
    match result:
        error(cause): return failure_code(cause)
        ok(value): return value
