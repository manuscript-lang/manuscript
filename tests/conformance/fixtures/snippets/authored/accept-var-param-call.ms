// conform: tags=mutation,functions,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn child(var c List[String]) Int {
	c.append("a")
	return 1
}

export fn main() Int {
	var c = ["x"]
	return child(c) - 1
}
// expect-exit: 0
