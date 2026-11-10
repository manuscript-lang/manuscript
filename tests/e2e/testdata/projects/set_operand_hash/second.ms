import Key from "./domain.ms"

impl Equal for Key:
    fn equals(other: Key) Bool: self.id % 10 == other.id % 10

impl Hashable for Key:
    fn hash() Int: self.id % 10 + 1000

export fn second_items() Set[Key]:
    return Set[Key]([Key(11, "right shared"), Key(3, "right only")])

export fn second_shared() Set[Key]:
    return Set[Key]([Key(11, "right shared")])

export fn second_empty() Set[Key]:
    return Set[Key]()
