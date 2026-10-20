# conform: tags=closures,formatter,generics,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/builtin_parity_test.go:51 TestNativeMethodRetainsGenericReceiverBounds
fn convert[T, U](values: List[T], transform: fn(value: T) U) List[U]:
    return values.map(transform: transform)
