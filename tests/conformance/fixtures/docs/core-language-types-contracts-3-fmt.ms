# conform: tags=control-flow,formatter,interfaces,match,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/contracts.md:37
# Rejected: amount does not match the contract's value label.
impl Increment for Offset:
    fn apply(amount: Int) Int:
        return amount + self.delta
