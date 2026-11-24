// conform: tags=closures,control-flow,diagnostics,interfaces,records,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/capture_lint_test.go:79 TestConcurrentCaptureLintDoesNotGuessMethodNames
interface Starter {
	fn start(operation fn() Void) Void
}

type Sequential { ... }

fn Sequential.start(operation fn() Void) Void {
	operation()
}

fn run() Void {
	var values = [0]
	Sequential().start(
		() => {
			values.append(1)
		}
	)
}
