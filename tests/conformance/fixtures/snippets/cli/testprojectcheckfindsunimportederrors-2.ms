// conform: tags=diagnostics,strings,tier-core
// conform: phase=check
// conform: origin=internal/cli/project_check_test.go:17 TestProjectCheckFindsUnimportedErrors
fn number() Int {
	return "wrong"
}

fn text() String {
	return 1
}
// expect-error: MS3001 5:12 expected Int, found String (in the return value)
// expect-error: MS3001 9:12 expected String, found Int (in the return value); Int does not convert to String implicitly; interpolate it into text, e.g. f"{value}"
// expect-fix: 9:12-9:13 "\"1\""
