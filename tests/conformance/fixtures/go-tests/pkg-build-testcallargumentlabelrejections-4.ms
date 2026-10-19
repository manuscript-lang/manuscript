# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:80 TestCallArgumentLabelRejections
fn call(operation: fn() Int) Int:
    return operation()
