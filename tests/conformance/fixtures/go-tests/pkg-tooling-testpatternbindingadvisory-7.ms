# conform: tags=alternatives,control-flow,diagnostics,interfaces,match,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:29 TestPatternBindingAdvisory
interface Describe:
    fn describe() String
type State:
    case Ready
    case Waiting
impl Describe for State:
    fn describe() String: "state"
fn use(value: Describe) Int:
    match value:
        State(Ready): return 1
        _: return 0
