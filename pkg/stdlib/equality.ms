# Equality and hashing are ordinary operation interfaces. Built-in data retains
# its value semantics; an explicit implementation selects domain identity.
export interface Equal:
    # Compares this value with another value in the same domain.
    fn equals(other: Equal) -> Bool

# A type with a total order; `compare` agrees with `equals` when both are implemented.
export interface Comparable:
    # Orders this value against another in the same domain: negative when it sorts before, zero when neither sorts first, positive when it sorts after.
    fn compare(other: Comparable) -> Int

# A type with a stable hash consistent with its `Equal` implementation.
export interface Hashable:
    # Returns a stable hash consistent with `equals` for the same value.
    fn hash() -> Int
