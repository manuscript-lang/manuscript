import range from "@std/collections.ms"
import panic from "@std/faults.ms"

type Shape:
    case Circle(radius: Float)

type Point:
    x: Int
    y: Int

fn roll(i: Int) -> Result[Int, String]: ok(i)

fn count(values: List[String]) -> Int: values.length()

fn update[K: Hashable, V](values: Map[K, V], key: K, value: V) -> Map[K, V]:
    return values.add(key, value)

test "issue 187 programs need no collection imports":
    let shapes = [Shape.Circle(1.0)]
    if shapes.length() != 1 or count(["/var", "log"]) != 2: return panic("literals")

    var rolls: List[Int] = []

    for i in range(0, 5):
        match roll(i):
            ok(n): rolls.append(n)
            error(_): return panic("roll")

    if rolls.length() != 5: return panic("annotation or match")

    let points = Map[Point, Int]()
    points.add(Point(1, 2), 7)
    if points.get(Point(1, 2)).unwrap() != 7: return panic("constructor")

    let nested: List[Map[String, List[Int]]] = [{}, {"a": []}]
    if nested[1].unwrap().get("a").unwrap().length() != 0: return panic("empty context")

test "map add returns receiver and retains aliases clone and insertion order":
    let values = {"a": 1, "b": 2}
    let alias = values
    let copy = values.clone()
    let returned = values.add("a", 3)
    returned.add(key: "c", value: 4)
    alias.add(value: 5, key: "b")
    let bound = values.add
    bound("d", 6)
    bound(value: 7, key: "a")
    values.add("e", 8)
    if alias.keys() != ["a", "b", "c", "d", "e"]: return panic("order")
    if alias.values() != [7, 5, 4, 6, 8]: return panic("receiver identity")
    if copy.keys() != ["a", "b"] or copy.values() != [1, 2]: return panic("clone")

    values.remove("b").add("b", 9)
    if values.keys() != ["a", "c", "d", "e", "b"]: return panic("reinsertion")

    let payload = [1]
    let nested = Map[Int, List[Int]]().add(1, payload)
    payload.append(2)
    if nested.get(1).unwrap() != [1, 2]: return panic("payload reference")

test "map add retains optional wrapping and generic bound calls":
    let values = Map[Optional[Int], Optional[Int]]()
    values.add(1, 2)
    values.add(value: 3, key: 1)
    let bound = values.add
    bound(4, 5)
    if values.get(1).unwrap().unwrap() != 3: return panic("optional conversion")
    if values.get(4).unwrap().unwrap() != 5: return panic("bound conversion")

    let generic = update[Optional[Int], Optional[Int]](values, some(6), some(7))
    generic.add(8, 9)
    if values.get(6).unwrap().unwrap() != 7 or values.get(8).unwrap().unwrap() != 9: return panic(
        "generic receiver"
    )

test "map add captures receivers and arguments in written order":
    let original = Map[Int, Int]()
    var selected = original
    let other = Map[Int, Int]()
    selected.add(
        match some(1):
            some(_):
                selected = other
                1
            none: 0
        ,
        2
    )
    if original.get(1).unwrap() != 2 or not other.is_empty(): return panic(
        "receiver capture"
    )

    var key = 3
    original.add(
        key,
        match some(1):
            some(_):
                key = 4
                5
            none: 0
    )
    if original.get(3).unwrap() != 5 or original.contains(4): return panic(
        "key capture"
    )

    var order = 0
    original.add(
        value: match some(1):
            some(_):
                order = 1
                7
            none: 0
        ,
        key: match some(1):
            some(_):
                if order != 1: return panic("reordered evaluation")

                order = 2
                6
            none: 0
    )
    if order != 2 or original.get(6).unwrap() != 7: return panic("reordered labels")
