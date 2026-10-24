# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:25 TestMutationRejections
def f() -> Unit:
    Val.val = 1
