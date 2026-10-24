# conform: tags=formatter,generics,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/builtin_parity_test.go:45 TestNativeMethodRetainsGenericReceiverBounds
def search[T: Equal](values: List[T], value: T) -> Bool:
    return values.contains(value: value)
