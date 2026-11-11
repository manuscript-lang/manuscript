// An unrelated receiver with the same display name.
export type Box[T]:
    value: T

// Reports that this is the other box.
fn Box[T].other() Bool:
    return true
