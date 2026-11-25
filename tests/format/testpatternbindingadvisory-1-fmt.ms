// conform: tags=alternatives,formatter,match,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/pattern_lint_test.go:22 TestPatternBindingAdvisory
enum Failure {
	NotFound
	Denied
}

enum Envelope {
	Pair(left Failure, right Failure)
}

fn use(value Envelope) Int {
	match value {
		Pair(_payload, NotFound) => return 1
	}
}
// expect-format: rewritten
// expect-formatted: enum Failure {
// expect-formatted: \tNotFound
// expect-formatted: \tDenied
// expect-formatted: }
// expect-formatted:
// expect-formatted: enum Envelope {
// expect-formatted: \tPair(left, right Failure)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn use(value Envelope) Int {
// expect-formatted: \tmatch value {
// expect-formatted: \t\tPair(_payload, NotFound) => return 1
// expect-formatted: \t}
// expect-formatted: }
