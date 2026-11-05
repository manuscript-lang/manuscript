// conform: tags=alternatives,diagnostics,match,records,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/pattern_lint_test.go:22 TestPatternBindingAdvisory
enum Failure:
    case NotFound
    case Denied

enum Envelope:
    case Pair(left: Failure, right: Failure)

fn use(value: Envelope) Int:
    match value:
        Pair(_payload, NotFound): return 1
