# conform: tags=diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:13 TestInterfaceAndReceiverHints
interface Shape:
    def area() -> Int

type Sq:
    s: Int
