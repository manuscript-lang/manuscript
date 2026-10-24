# conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:22 TestInterfaceAndReceiverHints
interface Read[T]:
    def get() -> T

type Box[T]:
    item: T

impl Read[T] for Box[T]:
    def get() -> T: self.item

def read() -> Read[Int]: Box(1)
