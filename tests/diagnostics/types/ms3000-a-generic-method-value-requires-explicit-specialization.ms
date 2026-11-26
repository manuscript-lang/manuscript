// conform: tags=diagnostics
// conform: phase=check
fn run(held Int!Error) Bool {
	f := held.map
	return f(m => m + 1).is_ok()
}
// expect-error: MS3000 4:15 a generic method value requires explicit specialization; write it with its type arguments, such as `result.map[Type]`, or call it with arguments
