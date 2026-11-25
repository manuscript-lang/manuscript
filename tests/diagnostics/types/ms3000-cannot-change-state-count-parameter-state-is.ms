// conform: tags=diagnostics
// conform: phase=check
type State {
	count Int
}

fn increment(state State) Int {
	state.count += 1
	return state.count
}

type Options {
	state State
	count Int = increment(state)
}

fn construct(state State) Options {
	return Options(state: state.clone())
}
// expect-error: MS3000 8:11 cannot change `state.count`: parameter `state` is not declared var; write `var state <Type>` in the signature
// expect-fix: 7:14-7:14 "var "
