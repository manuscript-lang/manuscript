// conform: tags=formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=pkg/tooling/review_test.go:53 TestReviewNamesErrorFlowAndContractChanges

export fn load(n Int) Int!Error {
	return ok(n)
}
// expect-format: rewritten
// expect-formatted:
// expect-formatted: export fn load(n Int) Int! {
// expect-formatted: \treturn ok(n)
// expect-formatted: }
