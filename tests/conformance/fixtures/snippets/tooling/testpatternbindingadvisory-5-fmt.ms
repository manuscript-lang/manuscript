# conform: tags=alternatives,formatter,match,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:27 TestPatternBindingAdvisory
type First:
    case Ready

type Second:
    case Ready

fn use(value: Int?) Int:
    match value:
        ready: return Ready
        none: return 0
