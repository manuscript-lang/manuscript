// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/diagnostic_fixes_test.go:34 TestDiagnosticFixes
fn f() Int {
	a := Set[Int]()
	b := Set[Int]()
	var m = Queue[Int]()
	var n = Queue[Int]()
	return 0
}
// expect-error: MS2001 7:13 unknown binding Queue; add: import Queue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import Queue from \"@std/collections/queue.ms\"\n"
// expect-error: MS2001 8:13 unknown binding Queue; add: import Queue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import Queue from \"@std/collections/queue.ms\"\n"
