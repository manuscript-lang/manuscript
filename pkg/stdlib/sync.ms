# Canonical standard-library declarations. Implementations are native.

export type Synchronized[T]:
    value: T
    fn lock() -> SynchronizedGuard[T]:

export type SynchronizedGuard[T]:
    fn get() -> T:
    fn set(value: T) -> Unit:
    fn close() -> Unit:
