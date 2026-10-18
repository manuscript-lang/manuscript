import panic from "@std/faults.ms"
import Synchronized from "@std/sync.ms"
import ListBuilder from "@std/collections.ms"
import MapBuilder from "@std/collections.ms"
import SetBuilder from "@std/collections.ms"
import BytesBuilder from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"

test "atomic state and sealed builders":
    let state = Synchronized(3)

    with locked = state.lock():
        if not (locked.get() == 3):
            return panic("check failed")

        locked.set(4)

    with locked = state.lock():
        if not (locked.get() == 4):
            return panic("check failed")
    let list = ListBuilder[Int]()
    list.append(1)
    list.append(2)
    if not (list.freeze() == [1, 2]):
        return panic("check failed")
    if not (list.freeze() == [1, 2]):
        return panic("check failed")

    let map = MapBuilder[String, Int]()
    map.add("a", 1)
    map.add("a", 2)
    let expected: Optional[Int] = some(2)
    if not (map.freeze().get("a") == expected):
        return panic("check failed")

    let set = SetBuilder[Int]()
    set.add(3)
    set.add(3)
    if not (set.freeze().length() == 1):
        return panic("check failed")

    let bytes = BytesBuilder()
    bytes.append(65)
    bytes.concat("B".to_bytes())
    let expected_text: Optional[String] = some("AB")
    if not (bytes.freeze().decode_utf8() == expected_text):
        return panic("check failed")

    let text = StringBuilder()
    text.append("hello")
    text.append(" world")
    if not (text.freeze() == "hello world"):
        return panic("check failed")
