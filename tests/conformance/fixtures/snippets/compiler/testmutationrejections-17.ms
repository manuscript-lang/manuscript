// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/mutation_test.go:38 TestMutationRejections
fn f(queue Queue[Int]) Void {
	queue.capacity = 1
}
// expect-error: MS2001 4:12 unknown type Queue; add: import Queue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import Queue from \"@std/collections/queue.ms\"\n"
// expect-error: MS3000 5:11 assignment requires a type field; only fields of a type value can be assigned with 'x.field = ...'
