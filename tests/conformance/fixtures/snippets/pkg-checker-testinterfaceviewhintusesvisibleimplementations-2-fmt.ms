# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:83 TestInterfaceViewHintUsesVisibleImplementations
from "data.ms" import Sq
from "extension.ms" import Shape

def shape() -> Shape: Sq(2)
