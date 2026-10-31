# conform: tags=formatter,generics,lists,parser,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/builtin_parity_test.go:48 TestNativeMethodRetainsGenericReceiverBounds
fn unique[T: Hashable & Clonable](values: List[T]) Set[T]:
    return values.to_set()
