# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:655 TestTypeBoundaries
fn invalid(value: fn() Int) Bool:
    return value == value
