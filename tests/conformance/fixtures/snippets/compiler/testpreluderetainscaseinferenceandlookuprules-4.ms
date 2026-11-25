// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:15 TestPreludeRetainsCaseInferenceAndLookupRules
fn f() Error {
	return "failed"
}
// expect-error: MS3001 5:12 expected Error, found String (in the return value); String does not convert to Error implicitly; make the error with Error("message"), e.g. error(Error("message"))
// expect-fix: 5:12-5:20 "Error(\"failed\")"
