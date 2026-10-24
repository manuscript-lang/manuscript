# conform: tags=aliasing,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:35 TestMutationRejections
def f(file: File) -> Unit:
    file.clone()
