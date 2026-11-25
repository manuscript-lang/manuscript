// conform: tags=diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/tooling/review_test.go:54 TestReviewNamesErrorFlowAndContractChanges
export fn load(n Int) Int! {
	return ok(n)
}
// expect-exit: 0
