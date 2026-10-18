import panic from "@std/faults.ms"

fn append_generic[T](values: List[Optional[T]], value: T) Unit:
    values.append(value)

type Failure:
    code: Int

impl Error for Failure:
    fn message() String: "failure"

test "direct append preserves checked argument conversions":
    let values: List[Optional[Int]] = []
    values.append(7)
    append_generic(values, 8)
    values.append(none)
    if values.at(0).get().get() != 7 or values.at(1).get().get() != 8:
        return panic("append lost some wrapping")
    if not values.at(2).get().is_none(): return panic("explicit none was wrapped")

    let flags: List[Optional[Bool]] = []
    flags.append(false)
    if flags.at(0).get().is_none() or flags.at(0).get().get():
        return panic("false became absent")

    let units: List[Optional[Unit]] = []
    units.append(unit)
    if units.at(0).get().is_none(): return panic("Unit became absent")

    let inner: Optional[Int] = none
    let nested: List[Optional[Optional[Int]]] = []
    nested.append(inner)
    if nested.at(0).get().is_none() or not nested.at(0).get().get().is_none():
        return panic("some(none) was flattened")

    let callbacks: List[Optional[fn(value: Int) Int]] = []
    callbacks.append(fn(value): value + 1)
    if callbacks.at(0).get().get()(7) != 8: return panic("callback conversion lost")

    let errors: List[Error] = []
    errors.append(Failure(1))
    if errors.at(0).get().message() != "failure": return panic("Error conversion lost")

    let results: List[Optional[Result[Int, Error]]] = []
    let failed: Result[Int, Failure] = error(Failure(2))
    results.append(failed)
    let widened = results.at(0).get().get()
    if widened.is_ok(): return panic("error became success")
    if widened.err().message() != "failure": return panic("Result error widening lost")

test "direct keyed calls preserve optional keys and values":
    let values: List[Optional[Int]] = []
    values.append(7)
    if not values.contains(7) or values.contains(8): return panic(
        "contains conversion lost"
    )

    let entries = Map[Optional[Int], Optional[Int]]()
    entries.add(7, 9)
    if not entries.contains(7) or entries.get(7).get().get() != 9:
        return panic("map conversion lost")

    entries.add(value: 10, key: 8)
    if entries.get(8).get().get() != 10: return panic("reordered fallback differs")

    let keys = Set[Optional[Int]]()
    keys.add(7)
    keys.add(none)
    if (not keys.contains(7) or not keys.contains(none) or keys.length() != 2):
        return panic("set conversion lost")

test "direct calls capture receiver and arguments in written order":
    let first: List[Optional[Int]] = []
    let second: List[Optional[Int]] = []
    var receiver = first
    receiver.append(
        (
            match some(7):
                some(value):
                    receiver = second
                    value
                none: 0
        ) + 0
    )
    if first.at(0).get().get() != 7 or not second.is_empty():
        return panic("receiver read moved past argument")

    let entries = Map[Int, Optional[Int]]()
    var key = 1
    entries.add(
        key,
        (
            match some(7):
                some(value):
                    key = 2
                    value
                none: 0
        ) + 0
    )
    if (entries.get(1).get().get() != 7 or entries.contains(2) or key != 2):
        return panic("key read moved past value")
