// conform: tags=diagnostics
// conform: phase=check
type State:
    count: Int
fn increment(state: State) Int:
    state.count = state.count + 1
    return state.count
type Options:
    state: State
    count: Int = increment(state)
fn construct(state: State) Options:
    return Options(state: state)
