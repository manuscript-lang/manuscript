// conform: tags=functions,tier-core
// conform: phase=run
fn main() Int?! {
	return error(Error("bad"))
}
// expect-exit: 1
// expect-stderr: error: bad
