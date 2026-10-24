# conform: tags=formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:32 TestMutationRejections
def f() -> Unit:
    var value = 1
    value += 1.5
