// conform: tags=testing,tier-core
// conform: phase=check
fn parse(text String) Int! {
	return ok(1)
}

// A statement that drops a Result loses its failure; `let _ =` drops it on purpose.
export fn main() Int {
	parse("1")
	return 0
}
// expect-error: MS3000 9:5 this statement discards Int!, so a failure would be lost; write a trailing '?' to propagate it, 'if value := x' or 'match' to handle it, or 'void ...' to drop it on purpose
