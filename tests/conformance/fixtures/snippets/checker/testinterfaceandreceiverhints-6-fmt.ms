# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:22 TestInterfaceAndReceiverHints
interface Read[T]:
    fn get() T

type Box[T: Clonable]:
    item: T

impl Read[T] for Box[T]:
    fn get() T: self.item.clone()

fn read() Read[Int]: Box(1)
