import Key from "./domain.ms"

impl Equal for Key:
	fn equals(other: Key) Bool: self.id % 10 == other.id % 10

impl Hashable for Key:
	fn hash() Int: self.id % 10

export fn first_items() Set[Key]:
	return Set[Key]([Key(1, "left shared"), Key(2, "left only")])
