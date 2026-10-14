# Canonical standard-library declarations. Implementations are native.

# Protects a value shared across tasks. Lock before reading or updating the value.
export type Synchronized[T]:
    # Initial constructor payload; retain its mutable aliases only with the same guarded access policy.
    value: T
    # Waits for an exclusive guard; caller cancellation interrupts a pending acquisition.
    # Keep the guard in a with scope so every exit releases it.
    fn lock() -> SynchronizedGuard[T]:

# Holds a synchronization lock. Closing the guard releases the lock.
export type SynchronizedGuard[T]:
    # Returns the original guarded payload, without cloning; a closed guard faults.
    fn get() -> T:
    # Replaces the guarded payload without copying it; a closed guard faults.
    fn set(value: T) -> Unit:
    # Releases the lock, waits for notify_all, then reacquires it before returning; re-check state in a loop.
    # Use it in a loop, such as: while queue_is_empty: locked.wait(). Only the acquiring task may call it. Cancellation interrupts the wait without reacquiring, leaving the guard released.
    fn wait() -> Unit:
    # Call it after changing the shared value so waiting tasks re-check it. It wakes every task waiting on this Synchronized; the guard must be open and owned by the caller.
    fn notify_all() -> Unit:
    # Releases the lock for every alias of this guard; repeated close does nothing.
    fn close() -> Unit:
