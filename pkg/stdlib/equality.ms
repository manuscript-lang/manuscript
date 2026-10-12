# Equality and hashing are ordinary operation interfaces. Built-in data retains
# its value semantics; an explicit implementation selects domain identity.
export interface Equal:
    fn equals(other: Equal) -> Bool

export interface Hashable:
    fn hash() -> Int
