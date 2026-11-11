// conform: tags=diagnostics
// conform: phase=check
interface Describe:
    fn describe() String
enum State:
    Ready
    Waiting
impl Describe for State:
    fn describe() String: "state"
fn use(value: Describe) Int:
    match value:
        State(Ready): return 1
        _: return 0
