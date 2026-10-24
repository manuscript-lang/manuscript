# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/contracts.md:83
interface ReadValue[T]:
    def get() -> T

type Box[T]:
    value: T

impl ReadValue[T] for Box[T]:
    def get() -> T:
        return self.value
