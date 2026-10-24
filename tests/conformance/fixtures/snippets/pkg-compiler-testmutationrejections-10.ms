# conform: tags=diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:31 TestMutationRejections
def f() -> Unit:
    var value = "a"
    value -= "b"
