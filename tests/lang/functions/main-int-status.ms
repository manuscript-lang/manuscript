// conform: tags=functions,tier-core
// conform: phase=run
fn main() Int?! {
	print("status")
	return ok(3)
}
// expect-exit: 3
// expect-stdout: status
