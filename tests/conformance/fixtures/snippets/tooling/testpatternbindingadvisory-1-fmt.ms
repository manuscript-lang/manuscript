// conform: tags=alternatives,formatter,match,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/pattern_lint_test.go:22 TestPatternBindingAdvisory
enum Failure:
    NotFound
    Denied

enum Envelope:
    Pair(left: Failure, right: Failure)

fn use(value: Envelope) Int:
    match value:
        Pair(_payload, NotFound): return 1
