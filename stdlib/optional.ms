# Canonical standard-library declarations. Implementations are native.


export type Optional[T]:
    case some(value: T)
    case none
