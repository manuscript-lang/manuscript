import panic from "@std/faults.ms"

type Box[T: Shareable]:
    value: T

fn unwrap[T: Shareable](box: Box[T]) -> T:
    return box.value

fn same[T: Shareable & Equal](left: T, right: T) -> Bool:
    return left == right

test "generic argument inference":
    let box = Box[Int](value: 6)
    if not (unwrap(box: box) == 6):
        return panic(message: "check failed")
    if not (unwrap[Int](box: box) == 6):
        return panic(message: "check failed")
    if not (same(left: 6, right: 6)):
        return panic(message: "check failed")
