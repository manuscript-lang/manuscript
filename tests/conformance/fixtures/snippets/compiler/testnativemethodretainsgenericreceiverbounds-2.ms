# conform: tags=diagnostics,generics,lists,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/builtin_parity_test.go:48 TestNativeMethodRetainsGenericReceiverBounds
fn unique[T: Hashable & Clonable](values: List[T]) Set[T]:
    return values.to_set()
