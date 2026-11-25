// conform: tags=closures,diagnostics,modules,stdlib-queues,tier-stdlib
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:50 TestDiagnosticsStateCauseAndFix
import PriorityQueue from "@std/collections/queue.ms"

fn f() Int {
	var q = PriorityQueue(
		compare: fn(left HttpMethod, right HttpMethod) Int => return 0
	)
	return 0
}
// expect-error: MS3080 7:13 cannot infer constructor type argument T; write the type arguments, e.g. Box[Int](...), or annotate the binding
// expect-error: MS3004 8:9 unknown argument compare; parameters of PriorityQueue: capacity, heap, next_order
// expect-error: MS2001 8:26 unknown type HttpMethod; add: import HttpMethod from "@std/net/http.ms"
// expect-fix: 1:1-1:1 "import HttpMethod from \"@std/net/http.ms\"\n"
// expect-error: MS2001 8:44 unknown type HttpMethod; add: import HttpMethod from "@std/net/http.ms"
// expect-fix: 1:1-1:1 "import HttpMethod from \"@std/net/http.ms\"\n"
