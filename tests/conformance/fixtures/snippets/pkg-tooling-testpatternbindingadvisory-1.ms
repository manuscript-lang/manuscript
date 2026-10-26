# conform: tags=alternatives,diagnostics,match,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:22 TestPatternBindingAdvisory
type Failure:
    case NotFound
    case Denied

type Envelope:
    case Pair(left: Failure, right: Failure)

def use(value: Envelope) -> Int:
    match value:
        case Pair(_payload, NotFound): return 1
