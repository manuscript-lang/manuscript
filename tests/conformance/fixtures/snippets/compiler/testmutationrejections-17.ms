// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/mutation_test.go:38 TestMutationRejections
fn f(queue Queue[Int]) Void:
    queue.capacity = 1
