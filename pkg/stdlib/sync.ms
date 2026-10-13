# Canonical standard-library declarations. Implementations are native.

# Protects a value shared across tasks. Lock before reading or updating the value.
export type Synchronized[T]:
    value: T
    fn lock() -> SynchronizedGuard[T]:

# Holds a synchronization lock. Closing the guard releases the lock.
export type SynchronizedGuard[T]:
    fn get() -> T:
    fn set(value: T) -> Unit:
    fn close() -> Unit:
