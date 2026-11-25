// conform: tags=control-flow,diagnostics,formatter,interfaces,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/library_test.go:91 TestCommonErrorRejectsInvalidContractPatterns
interface Diagnostic {
	fn message() String
}

type LocalError {
	detail String
}

fn LocalError.message() String {
	return self.detail.clone()
}

fn wrong(hold value LocalError) &Diagnostic {
	return value
}
// expect-exit: 0
