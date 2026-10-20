# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:80 TestCallArgumentLabelRejections
fn call(operation: fn() Int) Int:
    return operation()
