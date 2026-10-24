# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:23 TestMutationRejections
def f(value: Val) -> Unit:
    value.val = True
