// conform: tags=diagnostics
// conform: phase=check
type Impostor {
	detail String
}

fn wrong(value Impostor) Error {
	return value
}
// expect-error: MS3001 8:12 expected Error, found Impostor (in the return value)
