# conform: tags=aliasing,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:37 TestMutationRejections
def f(queue: Queue[Int]) -> Unit:
    queue.clone()
