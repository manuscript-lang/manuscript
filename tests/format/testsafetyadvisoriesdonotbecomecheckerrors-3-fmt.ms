// conform: tags=formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=internal/cli/advisory_lint_test.go:18 TestSafetyAdvisoriesDoNotBecomeCheckErrors

fn fail() Int!Error {
	return error(Error("boom"))
}

fn use() Void {
	void fail()
}
// expect-format: rewritten
// expect-formatted:
// expect-formatted: fn fail() Int! {
// expect-formatted: \treturn error(Error("boom"))
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn use() Void {
// expect-formatted: \tvoid fail()
// expect-formatted: }
