// conform: tags=functions,tier-core
// conform: phase=run
fn main() Void! {
	print("start")
	return error(Error("boom"))
}
// expect-exit: 1
// expect-stdout: start
// expect-stderr: error: boom
