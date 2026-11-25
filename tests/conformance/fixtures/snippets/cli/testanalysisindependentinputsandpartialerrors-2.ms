// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=internal/cli/analysis_test.go:33 TestAnalysisIndependentInputsAndPartialErrors
export fn main() Int {
	return "wrong"
}
// expect-error: MS3001 5:12 expected Int, found String (in the return value)
