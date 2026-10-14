import panic from "@std/faults.ms"

type Box[T, U = T]:
    first: T
    second: U

fn pick[T = Int](values: List[T]) -> Int:
    return values.length()

fn make[T = String]() -> Optional[T]:
    return none

fn pair[A, B = A](first: A, second: B) -> Box[A, B]:
    return Box[A, B](first, second)

test "omitted trailing type arguments use their defaults":
    let same: Box[Int] = Box[Int](1, 2)
    let mixed: Box[Int, String] = Box[Int, String](1, "x")
    if not (same.second == 2):
        return panic(message: "check failed")
    if not (mixed.second == "x"):
        return panic(message: "check failed")

test "constructors fall back to defaults":
    let b = Box[Int](first: 3, second: 4)
    if not (b.first + b.second == 7):
        return panic(message: "check failed")

test "calls infer first and only then use the default":
    let inferred = make()
    if not (inferred.is_none()):
        return panic(message: "check failed")

    let explicit: Optional[Int] = make()
    if not (explicit.is_none()):
        return panic(message: "check failed")
    if not (pick([1, 2, 3]) == 3):
        return panic(message: "check failed")
    if not (pair(1, "a").second == "a"):
        return panic(message: "check failed")
