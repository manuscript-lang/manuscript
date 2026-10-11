# Canonical standard-library declarations. Implementations are native.


export type State[T: Shareable]:
    value: T
    fn get() -> T
    fn set(value: T) -> Unit
    fn swap(value: T) -> T
