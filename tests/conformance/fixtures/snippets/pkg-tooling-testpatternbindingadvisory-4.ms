# conform: tags=alternatives,diagnostics,match,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:26 TestPatternBindingAdvisory
type Flag:
    case Ready

fn use(value: Int?) Int:
    match value:
        some(Ready): return Ready
        none: return 0
