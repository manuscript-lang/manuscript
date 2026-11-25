// conform: tags=diagnostics,records,strings,tier-core
// conform: phase=check
// conform: origin=pkg/build/library_test.go:101 TestCommonErrorRejectsInvalidContractPatterns
type Impostor {
	detail String
}

fn wrong(value Impostor) Error {
	return Error(value: value)
}
// expect-error: MS3004 9:18 unknown argument value; parameters of Error: details, kind, message
// expect-error: MS3003 9:12 missing argument message: String in call to Error; add 'message: <String>'
