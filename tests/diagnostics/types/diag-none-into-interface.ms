// conform: tags=diagnostics,interfaces,optional,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	r Equal := null
}
// expect-error: MS3080 5:16 cannot infer the type of null; give it a target, e.g. `x Int? := null`, or pass a value
