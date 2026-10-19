import {expect_equal} from "@std/testing.ms"
import ListBuilder from "@std/collections.ms"
import MapBuilder from "@std/collections.ms"
import SetBuilder from "@std/collections.ms"
import BytesBuilder from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"

test "sealed builders":
    let list = ListBuilder[Int]()
    list.append(1)
    list.append(2)
    try expect_equal(list.freeze(), [1, 2])
    try expect_equal(list.freeze(), [1, 2])
    let map = MapBuilder[String, Int]()
    map.add("a", 1)
    map.add("a", 2)
    let expected: Optional[Int] = some(2)
    try expect_equal(map.freeze().get("a"), expected)
    let set = SetBuilder[Int]()
    set.add(3)
    set.add(3)
    try expect_equal(set.freeze().length(), 1)
    var bytes = BytesBuilder()
    bytes.append(65)
    bytes.concat("B".to_bytes())
    let expected_text: Optional[String] = some("AB")
    try expect_equal(bytes.freeze().decode_utf8(), expected_text)
    var text = StringBuilder()
    text.append("hello")
    text.append(" world")
    try expect_equal(text.freeze(), "hello world")
