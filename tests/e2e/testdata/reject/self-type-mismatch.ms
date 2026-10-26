type Key:
    id: Int

type Other:
    id: Int

impl Equal for Key:
    def equals(other: Key) -> Bool:
        return self.id == other.id

def same[T: Equal](left: T, right: T) -> Bool:
    return left.equals(right)

export def main() -> Int:
    let key = Key(1)
    let other = Other(1)
    if key.equals(other):
        return 1

    return 0
