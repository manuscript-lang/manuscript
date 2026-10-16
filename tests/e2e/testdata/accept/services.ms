import panic from "@std/faults.ms"

import Synchronized from "@std/sync.ms"
import File from "@std/io.ms"
import IoError from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import ListBuilder from "@std/collections.ms"
import MapBuilder from "@std/collections.ms"
import SetBuilder from "@std/collections.ms"
import BytesBuilder from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"

test "atomic state and sealed builders":
    let state = Synchronized(3)

    with locked = state.lock():
        if not (locked.get() == 3):
            return panic(message: "check failed")

        locked.set(value: 4)

    with locked = state.lock():
        if not (locked.get() == 4):
            return panic(message: "check failed")

    let list = ListBuilder[Int]()
    list.append(value: 1)
    list.append(value: 2)
    if not (list.freeze() == [1, 2]):
        return panic(message: "check failed")
    if not (list.freeze() == [1, 2]):
        return panic(message: "check failed")

    let map = MapBuilder[String, Int]()
    map.add(key: "a", value: 1)
    map.add(key: "a", value: 2)
    let expected: Optional[Int] = some(2)
    if not (map.freeze().get(key: "a") == expected):
        return panic(message: "check failed")

    let set = SetBuilder[Int]()
    set.add(value: 3)
    set.add(value: 3)
    if not (set.freeze().length() == 1):
        return panic(message: "check failed")

    let bytes = BytesBuilder()
    bytes.append(value: 65)
    bytes.concat(values: "B".to_bytes())
    let expected_text: Optional[String] = some("AB")
    if not (bytes.freeze().to_string() == expected_text):
        return panic(message: "check failed")

    let text = StringBuilder()
    text.append(value: "hello")
    text.append(value: " world")
    if not (text.freeze() == "hello world"):
        return panic(message: "check failed")
