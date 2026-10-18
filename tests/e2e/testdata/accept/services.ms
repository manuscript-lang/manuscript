import {expect_equal} from "@std/testing.ms"
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
        locked.get() | try expect_equal(expected: 3)
        locked.set(value: 4)

    with locked = state.lock():
        locked.get() | try expect_equal(expected: 4)
    let list = ListBuilder[Int]()
    list.append(value: 1)
    list.append(value: 2)
    list.freeze() | try expect_equal(expected: [1, 2])
    list.freeze() | try expect_equal(expected: [1, 2])
    let map = MapBuilder[String, Int]()
    map.add(key: "a", value: 1)
    map.add(key: "a", value: 2)
    let expected: Optional[Int] = some(2)
    map.freeze().get(key: "a") | try expect_equal(expected: expected)
    let set = SetBuilder[Int]()
    set.add(value: 3)
    set.add(value: 3)
    set.freeze().length() | try expect_equal(expected: 1)
    let bytes = BytesBuilder()
    bytes.append(value: 65)
    bytes.concat(values: "B".to_bytes())
    let expected_text: Optional[String] = some("AB")
    bytes.freeze().to_string() | try expect_equal(expected: expected_text)
    let text = StringBuilder()
    text.append(value: "hello")
    text.append(value: " world")
    text.freeze() | try expect_equal(expected: "hello world")
