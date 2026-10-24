# conform: tags=diagnostics,generics,lists,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/builtin_parity_test.go:60 TestNativeMethodRetainsGenericReceiverBounds
def search[T](values: List[T], value: T) -> Bool:
    return values.contains(value: value)
