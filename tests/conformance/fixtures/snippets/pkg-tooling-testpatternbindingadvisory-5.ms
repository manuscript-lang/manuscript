# conform: tags=alternatives,diagnostics,match,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:27 TestPatternBindingAdvisory
type First:
    case Ready

type Second:
    case Ready

fn use(value: Optional[Int]) Int:
    match value:
        some(Ready): return Ready
        none: return 0
