# conform: tags=control-flow,diagnostics,interfaces,match,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/contracts.md:37
# Rejected: amount does not match the contract's value label.
impl Increment for Offset:
    fn apply(amount: Int) Int:
        return amount + self.delta
