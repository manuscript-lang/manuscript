# conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/contracts.md:83
interface ReadValue[T]:
    fn get() T

type Box[T: Clonable]:
    value: T

impl ReadValue[T] for Box[T]:
    fn get() T:
        return self.value.clone()
