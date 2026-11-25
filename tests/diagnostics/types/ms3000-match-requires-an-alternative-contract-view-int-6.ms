// conform: tags=diagnostics
// conform: phase=check
fn wrong(cause Error) String {
	match cause {
		_ => {
			return cause.message()
		}
		JsonError(value) => {
			return value.message()
		}
	}
}
// expect-error: MS3000 4:5 match requires an alternative, contract view, Int, String or Bool, found Error; match on a type with cases, or use if/else
