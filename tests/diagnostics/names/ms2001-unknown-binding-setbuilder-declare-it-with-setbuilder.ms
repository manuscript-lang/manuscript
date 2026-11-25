// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
	a := SetBuilder[Int]()
	b := SetBuilder[Int]()
	m := Queue[Int]()
	n := Queue[Int]()
	return 0
}
// expect-error: MS2001 4:10 unknown binding SetBuilder; declare it with 'SetBuilder := ...' before use, define 'fn SetBuilder(...) T { ... }', or import it from a module
// expect-error: MS2001 5:10 unknown binding SetBuilder; declare it with 'SetBuilder := ...' before use, define 'fn SetBuilder(...) T { ... }', or import it from a module
// expect-error: MS2001 6:10 unknown binding Queue; add: import Queue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import Queue from \"@std/collections/queue.ms\"\n"
// expect-error: MS2001 7:10 unknown binding Queue; add: import Queue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import Queue from \"@std/collections/queue.ms\"\n"
