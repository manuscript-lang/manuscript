# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/contracts.md:21
interface Increment:
    def apply(value: Int) -> Int

type Offset:
    delta: Int

impl Increment for Offset:
    def apply(value: Int) -> Int:
        return value + self.delta
