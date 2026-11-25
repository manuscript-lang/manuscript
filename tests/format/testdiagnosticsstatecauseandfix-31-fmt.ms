// conform: tags=closures,formatter,modules,parser,stdlib-queues,tier-stdlib
// conform: phase=parse
// conform: origin=pkg/checker/hints_test.go:50 TestDiagnosticsStateCauseAndFix
import PriorityQueue from "@std/collections/queue.ms"

fn f() Int {
	var q = PriorityQueue(
		compare: fn(left HttpMethod, right HttpMethod) Int => return 0
	)
	return 0
}
// expect-format: rewritten
// expect-formatted: import PriorityQueue from "@std/collections/queue.ms"
// expect-formatted:
// expect-formatted: fn f() Int {
// expect-formatted: \tvar q = PriorityQueue(compare: fn(left, right HttpMethod) Int => return 0)
// expect-formatted: \treturn 0
// expect-formatted: }
