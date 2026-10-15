import panic from "@std/faults.ms"

type Point:
    x: Int
    y: Int

impl Equal for Point:
    fn equals(other: Equal) -> Bool:
        match other:
            Point(value): return self.x == value.x
            _: return false

fn contains_generic[T: Equal](values: List[T], value: T) -> Bool:
    return values.contains(value)

test "list members match generic dispatch":
    let values: List[Int] = []
    values.append(1)
    values.append(2)
    if values.is_empty:
        return panic(message: "not empty")
    if not values.contains(2):
        return panic(message: "contains")
    if values.contains(3):
        return panic(message: "missing")

    let points: List[Point] = [Point(x: 1, y: 2)]
    if not points.contains(Point(x: 1, y: 2)):
        return panic(message: "record contains")
    if not contains_generic(values: points, value: Point(x: 1, y: 2)):
        return panic(message: "generic contains")

test "map and set members":
    let m: Map[String, Int] = {}
    let updated = m.add("a", 1).add("a", 2).add("b", 3)
    if not (updated.get("a").unwrap() == 2):
        return panic(message: "overwrite")
    if updated.get("z").is_some:
        return panic(message: "absent")
    if not updated.contains("b"):
        return panic(message: "map contains")

    let s: Set[Int] = Set()
    let grown = s.add(1).add(1).add(2)
    if not (grown.length == 2):
        return panic(message: "set size")
    if not grown.contains(2):
        return panic(message: "set contains")

test "string at":
    let text = "héllo"
    if not (text.at(1).unwrap() == "é"):
        return panic(message: "unicode")
    if text.at(10).is_some:
        return panic(message: "range")
