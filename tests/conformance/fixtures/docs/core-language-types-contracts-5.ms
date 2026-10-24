# conform: tags=control-flow,diagnostics,generics,interfaces,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/contracts.md:99
interface SameValue[T: Equal]:
    def same(other: T) -> Bool

impl SameValue[T] for Box[T]:
    def same(other: T) -> Bool:
        return self.value == other
