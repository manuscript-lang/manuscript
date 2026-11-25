// conform: tags=functions,tier-core
// conform: phase=run
fn step(n Int) Void! {
	if n > 2 {
		return error(Error("too big"))
	}

	print(f"step {n}")
}

fn main() Void! {
	step(1)?
	step(2)?
	step(3)?
	print("unreachable")
}
// expect-exit: 1
// expect-stdout: step 1
// expect-stdout: step 2
// expect-stderr: error: too big
