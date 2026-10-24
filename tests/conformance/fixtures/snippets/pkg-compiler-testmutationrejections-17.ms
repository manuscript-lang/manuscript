# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:38 TestMutationRejections
def f(queue: Queue[Int]) -> Unit:
    queue.capacity = 1
