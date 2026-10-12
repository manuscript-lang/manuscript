type Box[T]:
    value: T

fn unwrap[T](box: Box[T]) -> T:
    return box.value

fn same[T: Equal](left: T, right: T) -> Bool:
    return left == right

test "generic argument inference":
    let box = Box[Int](value: 6)
    assert unwrap(box: box) == 6
    assert unwrap[Int](box: box) == 6
    assert same(left: 6, right: 6)
