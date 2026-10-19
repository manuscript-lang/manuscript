# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:30 TestMutationRejections
fn f(value: Int) Unit:
    value -= 1
