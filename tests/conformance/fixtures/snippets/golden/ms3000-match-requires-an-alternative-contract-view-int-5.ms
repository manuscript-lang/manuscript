// conform: tags=diagnostics
// conform: phase=check
fn wrong(cause Error) String {
	match cause {
		JsonError(first) => {
			return first.message()
		}
		JsonError(second) => {
			return second.message()
		}
		_ => {
			return cause.message()
		}
	}
}
// expect-error: MS3000 4:5 match requires an alternative, contract view, Int, String or Bool, found Error; match on a type with cases, or use if/else
