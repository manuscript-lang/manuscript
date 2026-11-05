// conform: tags=alternatives,diagnostics,match,optional,records,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/pattern_lint_test.go:27 TestPatternBindingAdvisory
enum First:
    case Ready

enum Second:
    case Ready

fn use(value: Int?) Int:
    match value:
        ready: return Ready
        none: return 0
