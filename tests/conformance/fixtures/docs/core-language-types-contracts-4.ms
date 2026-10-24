# conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/contracts.md:83
interface ReadValue[T]:
    def get() -> T

type Box[T]:
    value: T

impl ReadValue[T] for Box[T]:
    def get() -> T:
        return self.value
