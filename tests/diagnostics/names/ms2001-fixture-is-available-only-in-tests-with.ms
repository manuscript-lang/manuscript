// conform: tags=diagnostics
// conform: phase=check
test "test" {
	value := fixture.value
}
// expect-error: MS2001 4:14 fixture is available only in tests with a local make_fixture factory; declare fn make_fixture() returning a concrete TestHooks implementer in this file
