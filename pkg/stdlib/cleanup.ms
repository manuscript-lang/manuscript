# Canonical standard-library declarations. Implementations are native.

# A resource that can be closed. `with` closes a bound resource on every exit.
export interface Closeable:
    # Releases the implementation's resource state; with calls this on every scope exit.
    # Cleanup runs during return, expected errors, faults, and cancellation too.
    fn close() -> Unit
