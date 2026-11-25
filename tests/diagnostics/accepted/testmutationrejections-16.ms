// conform: tags=aliasing,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:37 TestMutationRejections
fn f(queue Queue[Int]) Void {
	queue.clone()
}
// expect-error: MS2001 4:12 unknown type Queue; add: import Queue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import Queue from \"@std/collections/queue.ms\"\n"
