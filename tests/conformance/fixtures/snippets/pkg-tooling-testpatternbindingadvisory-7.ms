# conform: tags=alternatives,control-flow,diagnostics,interfaces,match,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:29 TestPatternBindingAdvisory
interface Describe:
    def describe() -> String

type State:
    case Ready
    case Waiting

impl Describe for State:
    def describe() -> String: "state"

def use(value: Describe) -> Int:
    match value:
        case State(Ready): return 1
        case _: return 0
