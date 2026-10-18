import panic from "@std/faults.ms"

type Box[T]:
    value: T

fn unwrap[T](box: Box[T]) T:
    return box.value

fn same[T: Equal](left: T, right: T) Bool:
    return left == right

test "generic argument inference":
    let box = Box[Int](6)
    if not (unwrap(box) == 6):
        return panic("check failed")
    if not (unwrap[Int](box) == 6):
        return panic("check failed")
    if not (same(6, 6)):
        return panic("check failed")
