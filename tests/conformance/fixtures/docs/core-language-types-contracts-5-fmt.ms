# conform: tags=control-flow,formatter,generics,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/contracts.md:99
interface SameValue[T: Equal]:
    fn same(other: T) Bool

impl SameValue[T] for Box[T]:
    fn same(other: T) Bool:
        return self.value == other
