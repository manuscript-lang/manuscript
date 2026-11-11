// conform: tags=control-flow,diagnostics,interfaces,records,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/contracts.md:21
interface Increment:
    fn apply(value: Int) Int

type Offset:
    delta: Int

fn Offset.apply(value: Int) Int:
    return value + self.delta
