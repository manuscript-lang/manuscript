// conform: tags=diagnostics
// conform: phase=check
type Other {
	detail String
}

fn wrong(cause Error) String {
	match cause {
		Other(value) => {
			return value.detail
		}
		_ => {
			return cause.message()
		}
	}
}
// expect-error: MS3000 8:5 match requires an alternative, contract view, Int, String or Bool, found Error; match on a type with cases, or use if/else
