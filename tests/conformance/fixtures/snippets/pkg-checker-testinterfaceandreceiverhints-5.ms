# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:21 TestInterfaceAndReceiverHints
fn area(shape: Shape) Int: shape.area()

fn run() Int: area(Sq(2))
