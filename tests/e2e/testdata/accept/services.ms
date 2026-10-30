import expect_equal from "@std/test.ms"
import ListBuilder from "@std/collections.ms"
import MapBuilder from "@std/collections.ms"
import SetBuilder from "@std/collections.ms"
import BytesBuilder from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"

test "sealed builders":
    var list = ListBuilder[Int]()
    list.append(1)
    list.append(2)
    try expect_equal(list.build(), [1, 2])
    try expect_equal(list.build(), [1, 2])

    var map = MapBuilder[String, Int]()
    map.add("a", 1)
    map.add("a", 2)

    let expected: Int? = some(2)
    try expect_equal(map.build().get("a"), expected)

    var set = SetBuilder[Int]()
    set.add(3)
    set.add(3)
    try expect_equal(set.build().length(), 1)

    var bytes = BytesBuilder()
    bytes.append(65)
    bytes.append_bytes("B".to_bytes())

    let expected_text: String? = some("AB")
    try expect_equal(bytes.build().decode_utf8(), expected_text)

    var text = StringBuilder()
    text.append("hello")
    text.append(" world")
    try expect_equal(text.build(), "hello world")
