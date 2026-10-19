# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:65 TestCallArgumentLabelRejections
let transform = fn(item: Int) Int:
        return item
    apply(transform)
