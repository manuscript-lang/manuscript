// conform: tags=testing,tier-core
// conform: phase=check
type Key:
	id: Int

impl Equal for Key:
	fn equals(other: Equal) Bool:
		return true

export fn main() Int:
	return 0
