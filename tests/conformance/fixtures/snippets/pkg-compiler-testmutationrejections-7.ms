# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:28 TestMutationRejections
def f(value: Val) -> Unit:
    value = Val(val: 1)
