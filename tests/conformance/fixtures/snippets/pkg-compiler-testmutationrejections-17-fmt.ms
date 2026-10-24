# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:38 TestMutationRejections
def f(queue: Queue[Int]) -> Unit:
    queue.capacity = 1
