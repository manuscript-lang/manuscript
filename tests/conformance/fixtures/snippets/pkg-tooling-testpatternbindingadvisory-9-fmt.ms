# conform: tags=alternatives,formatter,match,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:31 TestPatternBindingAdvisory
type Flag:
    case Ready

fn use(value: Int?) Int:
    let _Flag = 2

    match value:
        some(Ready): return Ready
        none: return 0
