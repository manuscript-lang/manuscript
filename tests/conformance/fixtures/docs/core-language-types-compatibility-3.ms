// conform: tags=diagnostics,formatter,modules,records,stdlib-errors,tier-stdlib,try-result
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/compatibility.md:69

fn known() Result[Int, Error] {
	number Int := Result[Int, Error].ok(1)?
	return ok(number)
}

fn unknown() Result[Int, Error] {
	// Rejected: the operand?'s error type is undetermined.
	number Int := ok(1)?
	return ok(number)
}
// expect-error: MS3080 12:19 cannot infer constructor type argument E; write the type arguments, e.g. Box[Int](...), or annotate the binding
// expect-error: MS3000 12:19 '?' requires the same error type; this function returns Result[Int, Error] but the operand fails with <invalid>, so change the return error type or translate the error with map_error
