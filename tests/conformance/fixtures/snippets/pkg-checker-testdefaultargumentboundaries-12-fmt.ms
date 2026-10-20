# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:25 TestDefaultArgumentBoundaries
fn f(value: Int = 1) Int:
    return value
fn make() fn(value: Int) Int:
    return f
fn call() Int:
    return make()()
