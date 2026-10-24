# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/int_bounds_test.go:37 TestScalarIntBoundsLowering
def identity[T](value: T) -> T: return value

def effect(value: Int) -> Int: return value + 1
