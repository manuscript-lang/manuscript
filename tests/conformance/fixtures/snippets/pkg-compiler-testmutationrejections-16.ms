# conform: tags=aliasing,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:37 TestMutationRejections
fn f(queue: Queue[Int]) Unit:
    queue.clone()
