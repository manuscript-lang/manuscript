# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/int_bounds_test.go:37 TestScalarIntBoundsLowering
fn identity[T](value: T) T: return value
fn effect(value: Int) Int: return value + 1
