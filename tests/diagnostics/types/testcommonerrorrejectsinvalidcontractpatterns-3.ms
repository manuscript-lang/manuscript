// conform: tags=diagnostics,formatter,strings,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/build/library_test.go:79 TestCommonErrorRejectsInvalidContractPatterns
fn wrong() String! {
	return Result[Int, Error].ok(value: 1)
}
// expect-error: MS3001 5:31 expected Result[String, Error], found Result[Int, Error] (in the return value)
