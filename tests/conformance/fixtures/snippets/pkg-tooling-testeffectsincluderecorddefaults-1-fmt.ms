# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/effects_test.go:73 TestEffectsIncludeRecordDefaults
type State:
    count: Int

fn increment(var state: State) Int:
    state.count = state.count + 1
    return state.count

type Options:
    state: State
    count: Int = increment(state)

fn construct(state: State) Options:
    return Options(state: state)
