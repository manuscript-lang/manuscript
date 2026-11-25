// conform: tags=diagnostics,formatter,modules,stdlib-queues,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/checker/diagnostic_fixes_test.go:31 TestDiagnosticFixes
import Queue from "@std/collections/queue.ms"

fn f(q Queue[Int]) Int {
	q.capacity = 5
	return q.capacity
}
// expect-error: MS3001 8:14 expected Int, found Int? (in the return value); Int? may be absent; test it first with 'if x != null', or give a default with 'x or default'
