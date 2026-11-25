// conform: tags=diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int {
	var x Int = null
	return x
}
// expect-error: MS3001 5:17 expected Int, found null (in the initializer of 'x'); null is absent, so it fits only an Optional position: declare the target Int? or give a value
