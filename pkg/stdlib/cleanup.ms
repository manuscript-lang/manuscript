# Canonical standard-library declarations. Implementations are native.

# A resource that can be closed. `with` closes a bound resource on every exit.
export interface Closeable:
    fn close() -> Unit
