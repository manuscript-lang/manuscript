# conform: tags=closures,diagnostics,generics,lists,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/builtin_parity_test.go:51 TestNativeMethodRetainsGenericReceiverBounds
fn convert[T, U](values: List[T], transform: fn(T) U) List[U]:
    return values.map(transform: transform)
