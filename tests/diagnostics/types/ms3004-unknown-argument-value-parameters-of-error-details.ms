// conform: tags=diagnostics
// conform: phase=check
type Impostor {
	detail String
}

fn wrong(value Impostor) Error {
	return Error(value: value)
}
// expect-error: MS3004 8:18 unknown argument value; parameters of Error: details, kind, message
// expect-error: MS3003 8:12 missing argument message: String in call to Error; add 'message: <String>'
