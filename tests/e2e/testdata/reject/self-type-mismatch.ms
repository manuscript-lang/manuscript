type Key:
    id: Int

type Other:
    id: Int

impl Equal for Key:
    fn equals(other: Key) Bool:
        return self.id == other.id

fn same[T: Equal](left: T, right: T) Bool:
    return left.equals(right)

export fn main() Int:
    let key = Key(1)
    let other = Other(1)
    if key.equals(other):
        return 1

    return 0
