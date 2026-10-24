# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/contracts.md:21
interface Increment:
    def apply(value: Int) -> Int

type Offset:
    delta: Int

impl Increment for Offset:
    def apply(value: Int) -> Int:
        return value + self.delta
