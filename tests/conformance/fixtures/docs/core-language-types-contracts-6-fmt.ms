# conform: tags=control-flow,formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/contracts.md:112
# Rejected alongside the generic block above: both apply to Box[Int].
impl ReadValue[Int] for Box[Int]:
    fn get() Int:
        return self.value
