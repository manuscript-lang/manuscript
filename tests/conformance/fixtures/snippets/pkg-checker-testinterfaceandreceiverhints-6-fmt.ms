# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:22 TestInterfaceAndReceiverHints
interface Read[T]:
    def get() -> T

type Box[T]:
    item: T

impl Read[T] for Box[T]:
    def get() -> T: self.item

def read() -> Read[Int]: Box(1)
