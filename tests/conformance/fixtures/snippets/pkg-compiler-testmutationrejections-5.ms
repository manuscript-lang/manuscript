# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:26 TestMutationRejections
def f(value: Val) -> Unit:
    value.get = 1
