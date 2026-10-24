# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:21 TestInterfaceAndReceiverHints
def area(shape: Shape) -> Int: shape.area()

def run() -> Int: area(Sq(2))
