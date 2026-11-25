// conform: tags=diagnostics,formatter,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/library_test.go:74 TestCommonErrorRejectsInvalidContractPatterns
type Impostor {
	detail String
}

fn wrong(value Impostor) Error {
	return value
}
// expect-error: MS3001 9:12 expected Error, found Impostor (in the return value)
