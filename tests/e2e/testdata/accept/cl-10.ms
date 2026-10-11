interface Increment:
    fn apply(value: Int) -> Int

type Offset:
    delta: Int

impl Increment for Offset:
    fn apply(value: Int) -> Int:
        return value + self.delta

fn use_increment(operation: Increment) -> Int:
    return operation.apply(value: 4)

test "explicit contract conversion":
    let offset = Offset(delta: 1)
    let operation = Increment(value: offset)
    let same_view = Increment(value: operation)
    assert use_increment(operation: same_view) == 5
