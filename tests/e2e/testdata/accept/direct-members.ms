import panic from "@std/faults.ms"

type Point:
    x: Int
    y: Int

impl Equal for Point:
    fn equals(other: Equal) Bool:
        match other:
            Point(value): return self.x == value.x
            _: return false

fn contains_generic[T: Equal](values: List[T], value: T) Bool:
    return values.contains(value)

test "list members match generic dispatch":
    let values: List[Int] = []
    values.append(1)
    values.append(2)
    if values.is_empty():
        return panic("not empty")
    if not values.contains(2):
        return panic("contains")
    if values.contains(3):
        return panic("missing")

    let points: List[Point] = [Point(1, 2)]
    if not points.contains(Point(1, 2)):
        return panic("record contains")
    if not contains_generic(points, Point(1, 2)):
        return panic("generic contains")

test "map and set members":
    let m: Map[String, Int] = {}
    let updated = m.add("a", 1).add("a", 2).add("b", 3)
    if not (updated.get("a").unwrap() == 2):
        return panic("overwrite")
    if updated.get("z").is_some():
        return panic("absent")
    if not updated.contains("b"):
        return panic("map contains")

    let s: Set[Int] = Set()
    let grown = s.add(1).add(1).add(2)
    if not (grown.length() == 2):
        return panic("set size")
    if not grown.contains(2):
        return panic("set contains")

test "string at":
    let text = "héllo"
    if not (text.at(1).unwrap() == "é"):
        return panic("unicode")
    if text.at(10).is_some():
        return panic("range")
