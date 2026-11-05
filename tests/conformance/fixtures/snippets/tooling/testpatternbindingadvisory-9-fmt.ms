// conform: tags=alternatives,formatter,match,optional,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/pattern_lint_test.go:31 TestPatternBindingAdvisory
enum Flag:
    case Ready

fn use(value: Int?) Int:
    let _Flag = 2

    match value:
        ready: return Ready
        none: return 0
