# An unrelated receiver with the same display name.
export type Box[T]:
    value: T

impl Box[T]:
    # Reports that this is the other box.
    fn other() Bool:
        return true
