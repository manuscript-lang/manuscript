// conform: tags=aliasing,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:37 TestMutationRejections
fn f(queue Queue[Int]) Void {
	queue.clone()
}
