# conform: tags=aliasing,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:35 TestMutationRejections
fn f(file: File) Unit:
    file.clone()
