// conform: tags=diagnostics,formatter,mutation,numbers,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/basics/bindings.md:64
fn example() Void {
	var remaining = 3
	remaining = 2
	remaining = 2.0  // Rejected: Float cannot replace Int.
}
// expect-error: MS3001 7:17 expected Int, found Float; Float does not convert to Int implicitly; truncate_to_int() returns Int?, so unwrap it, e.g. value.truncate_to_int().get_or(0)
