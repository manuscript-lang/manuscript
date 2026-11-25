// conform: tags=testing,tier-core
// conform: phase=check
// `.clone()` of a record that holds a function value is accepted: a function value never
// changes once made, so the copy shares it.
type Handler {
	run fn(Int) Int
}

export fn main() Int {
	first := Handler(run: x => x * 2)
	again := first.clone()
	return again.run(2)
}
// expect-exit: 0
